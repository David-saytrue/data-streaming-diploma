# =====================================================================
# AdventureWorks CDC -> Lakehouse - full terminal demo
# =====================================================================
# Run (full demo WITH INSERT):
#   cd c:\UG_LAST\data-streaming-diploma
#   .\demo-pipeline.ps1 -SkipInfra
#
# Options:
#   -SkipInfra    skip docker up, Debezium, Flink, dim_date
#   -SkipInsert   skip step [2] INSERT (read-only replay)
#   -WaitSeconds  seconds before Presto queries (default 20)
# =====================================================================

param(
    [switch]$SkipInfra,
    [switch]$SkipInsert,
    [int]$WaitSeconds = 20
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-Step {
    param([string]$Num, [string]$Title, [string]$Route = "")
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host "[$Num] $Title" -ForegroundColor Cyan
    if ($Route) { Write-Host "    PATH: $Route" -ForegroundColor DarkCyan }
    Write-Host ("=" * 72) -ForegroundColor Cyan
}

function Invoke-DockerCmd {
    param([string[]]$DockerArgs)
    & docker @DockerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "docker failed: docker $($DockerArgs -join ' ') (exit $LASTEXITCODE)"
    }
}

function Invoke-PrestoQuery {
    param([string]$Schema, [string]$Sql)
    Invoke-DockerCmd -DockerArgs @(
        "exec", $presto, "/opt/presto-cli",
        "--catalog", "iceberg", "--schema", $Schema,
        "--execute", $Sql
    )
}

$pg     = "data-streaming-diploma-postgres-1"
$kafka  = "data-streaming-diploma-kafka-1"
$jm     = "data-streaming-diploma-jobmanager-1"
$presto = "data-streaming-diploma-presto-1"

Write-Host ""
Write-Host "  [1] PostgreSQL -> [2] Debezium -> [3] Kafka -> [4] Flink -> [5] Iceberg/MinIO -> [6] Presto"
Write-Host ""

if (-not $SkipInfra) {
    Write-Step -Num "A" -Title "Infrastructure" -Route "docker compose up -d"
    Invoke-DockerCmd -DockerArgs @("compose", "up", "-d")
    Write-Host "Waiting for services (45 sec)..." -ForegroundColor Gray
    Start-Sleep -Seconds 45
    Invoke-DockerCmd -DockerArgs @("compose", "ps")

    Write-Step -Num "B" -Title "Debezium connector" -Route "POST http://localhost:8083/connectors"
    $json = Get-Content "register-connector.json" -Raw
    try {
        $reg = Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -Body $json -ContentType "application/json"
        Write-Host "Created: $($reg.name)" -ForegroundColor Green
    }
    catch {
        $msg = $_.Exception.Message
        if ($msg -match "409|already exists|Already exists") {
            Write-Host "Connector already exists - continuing." -ForegroundColor Yellow
        }
        else {
            throw
        }
    }
    $status = Invoke-RestMethod "http://localhost:8083/connectors/adventureworks-connector/status"
    Write-Host "Connector state: $($status.connector.state)"
    Write-Host "Task state:      $($status.tasks[0].state)"

    Write-Step -Num "C" -Title "Flink streaming job" -Route "Kafka -> Iceberg Bronze + Gold"
    Write-Host "Running flink_job.sql (may take 1-3 min)..." -ForegroundColor Gray
    Invoke-DockerCmd -DockerArgs @("exec", $jm, "/opt/flink/bin/sql-client.sh", "-f", "/opt/flink/flink_job.sql")
    Write-Host "Flink UI: http://localhost:8081  job: adventureworks-cdc-lakehouse" -ForegroundColor Gray

    Write-Step -Num "D" -Title "dim_date one-shot" -Route "Presto -> iceberg.gold.dim_date"
    Invoke-DockerCmd -DockerArgs @("exec", "-i", $presto, "/opt/presto-cli", "--catalog", "iceberg", "--schema", "gold", "-f", "/opt/presto-server/etc/sql/dim_date.sql")
}

Write-Step -Num "1" -Title "PostgreSQL BEFORE change" -Route "[1] OLTP source"
Invoke-DockerCmd -DockerArgs @("exec", $pg, "psql", "-U", "postgres", "-d", "adventureworks", "-c", "SELECT COUNT(*) AS order_count FROM sales.sales_order_header;")

if (-not $SkipInsert) {
    Write-Step -Num "2" -Title "PostgreSQL CHANGE (INSERT)" -Route "[1] WAL -> [2] Debezium -> [3] Kafka"
    Write-Host "Adding: 1 order header + 1 line (product 11, qty 2, GEL)..." -ForegroundColor Gray

    # Kafka listener FIRST (latest offset), then INSERT -> catches new CDC events
    Write-Host "Starting Kafka listener (background, 25s)..." -ForegroundColor Gray
    $kafkaJob = Start-Job -ScriptBlock {
        param($Container)
        & docker exec $Container /kafka/bin/kafka-console-consumer.sh `
            --bootstrap-server kafka:9092 `
            --topic aw.sales.sales_order_header `
            --partition 0 `
            --offset latest `
            --max-messages 2 `
            --timeout-ms 25000 2>&1
    } -ArgumentList $kafka

    Start-Sleep -Seconds 2

    $insertSql = @"
WITH new_order AS (
    INSERT INTO sales.sales_order_header
        (order_date, ship_date, status, customer_id, sales_person_id, territory_id,
         currency_code, sub_total, tax_amt, freight, total_due)
    VALUES (NOW(), NOW(), 1, 1, 1, 1, 'GEL', 19.98, 2.00, 3.00, 24.98)
    RETURNING sales_order_id
)
INSERT INTO sales.sales_order_detail
    (sales_order_id, product_id, order_qty, unit_price, unit_price_discount)
SELECT sales_order_id, 11, 2, 9.99, 0.0000 FROM new_order
RETURNING sales_order_id, sales_order_detail_id;
"@
    Invoke-DockerCmd -DockerArgs @("exec", $pg, "psql", "-U", "postgres", "-d", "adventureworks", "-c", $insertSql)

    Write-Host "Waiting for Debezium -> Kafka (5 sec)..." -ForegroundColor Gray
    Start-Sleep -Seconds 5

    $script:KafkaCaptureJob = $kafkaJob
}
else {
    Write-Step -Num "2" -Title "PostgreSQL CHANGE (INSERT)" -Route "SKIPPED (-SkipInsert)"
    Write-Host "No new INSERT. Using existing rows from earlier demo." -ForegroundColor Yellow
}

Write-Step -Num "3" -Title "PostgreSQL AFTER change" -Route "[1] confirm rows"
$sqlAfter = "SELECT h.sales_order_id, h.total_due, d.sales_order_detail_id, d.line_total FROM sales.sales_order_header h JOIN sales.sales_order_detail d ON d.sales_order_id = h.sales_order_id ORDER BY h.sales_order_id DESC LIMIT 3;"
Invoke-DockerCmd -DockerArgs @("exec", $pg, "psql", "-U", "postgres", "-d", "adventureworks", "-c", $sqlAfter)

Write-Step -Num "4" -Title "Kafka CDC event" -Route "[1] -> [2] Debezium -> [3] topic aw.sales.sales_order_header"
if ($script:KafkaCaptureJob) {
    Write-Host "topic aw.sales.sales_order_header (events after INSERT from step [2])" -ForegroundColor Gray
    $null = Wait-Job $script:KafkaCaptureJob -Timeout 30
    $kafkaOut = Receive-Job $script:KafkaCaptureJob
    Remove-Job $script:KafkaCaptureJob -Force -ErrorAction SilentlyContinue
    if ($kafkaOut) { $kafkaOut | ForEach-Object { Write-Host $_ } }
    else {
        Write-Host "No messages captured in time. Fallback: last events from topic start..." -ForegroundColor Yellow
        & docker exec $kafka /kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 `
            --topic aw.sales.sales_order_header --from-beginning --max-messages 2 --timeout-ms 10000 2>&1 | ForEach-Object { Write-Host $_ }
    }
}
else {
    Write-Host "topic aw.sales.sales_order_header (sample from beginning, 2 msgs)" -ForegroundColor Gray
    & docker exec $kafka /kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 `
        --topic aw.sales.sales_order_header --from-beginning --max-messages 2 --timeout-ms 10000 2>&1 | ForEach-Object { Write-Host $_ }
}

Write-Host "Waiting for Flink checkpoint ($WaitSeconds sec)..." -ForegroundColor Gray
Start-Sleep -Seconds $WaitSeconds

Write-Step -Num "5" -Title "Bronze layer (raw CDC)" -Route "[3] -> [4] Flink -> [5] iceberg.bronze"
Invoke-PrestoQuery -Schema "bronze" -Sql "SELECT sales_order_id, order_ts, total_due FROM br_sales_order_header ORDER BY sales_order_id DESC LIMIT 5"
Invoke-PrestoQuery -Schema "bronze" -Sql "SELECT sales_order_id, sales_order_detail_id, product_id, line_total FROM br_sales_order_detail ORDER BY sales_order_id DESC LIMIT 5"

Write-Step -Num "6" -Title "Gold layer (star schema fact)" -Route "[4] joins -> [5] iceberg.gold -> [6] Presto"
Invoke-PrestoQuery -Schema "gold" -Sql "SELECT sales_order_id, sales_order_detail_id, order_ts, customer_id, product_id, line_total FROM fact_sales_order_line ORDER BY order_ts DESC NULLS LAST LIMIT 5"

Write-Step -Num "7" -Title "Physical storage" -Route "[5] Parquet files on MinIO"
Write-Host "MinIO Console: http://localhost:9001  user: admin  pass: adminpassword" -ForegroundColor Green
Write-Host "Bucket: lakehouse-admin / iceberg_data" -ForegroundColor Green

Write-Host ""
Write-Host "DONE. If Bronze/Gold empty: check Flink http://localhost:8081 (RUNNING), wait longer, rerun: .\demo-pipeline.ps1 -SkipInfra" -ForegroundColor Yellow
Write-Host ""
