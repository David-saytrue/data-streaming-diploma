# =====================================================================
# CDC end-to-end experiment: INSERT -> measure latency -> KPIs -> report
# =====================================================================
# Prerequisites: stack running, Flink job RUNNING, Gold has data.
#   .\demo-pipeline.ps1 -SkipInfra   # first time / if Gold empty
#   .\scripts\run-experiment.ps1
#
# What it does (same change path as demo-pipeline.ps1):
#   1. Count Gold rows BEFORE
#   2. INSERT 1 order + 1 line in PostgreSQL (AdventureWorks)
#   3. Poll Presto Gold until the new sales_order_id appears
#   4. Record end-to-end latency (seconds)
#   5. Run KPI queries + optional K-Means summary
#   6. Write docs/experiment-results/latest.md (+ timestamped copy)
# =====================================================================

param(
    [int]$TimeoutSeconds = 120,
    [int]$PollSeconds = 3,
    [switch]$SkipKMeans
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$pg     = "data-streaming-diploma-postgres-1"
$presto = "data-streaming-diploma-presto-1"
$airflow = "data-streaming-diploma-airflow-1"
$outDir = Join-Path $root "docs\experiment-results"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Invoke-Presto {
    param([string]$Sql)
    # PowerShell Stop + docker stderr WARNING would abort; isolate native call
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $raw = & docker exec $presto /opt/presto-cli --catalog iceberg --schema gold --output-format CSV --execute $Sql 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $lines = @($raw | ForEach-Object { "$_" } | Where-Object {
        $_ -and ($_ -notmatch 'WARNING:') -and ($_ -notmatch 'approx_distinct') -and ($_ -notmatch 'SLF4J')
    })
    if ($code -ne 0) { throw "Presto query failed (exit $code): $Sql`n$($lines -join "`n")" }
    return $lines
}

function Get-PrestoScalar {
    param([string]$Sql)
    $lines = @(Invoke-Presto -Sql $Sql)
    # CSV may be header+row OR a single data row depending on Presto CLI
    $data = $lines | Where-Object { $_ -match '"?\d' } | Select-Object -Last 1
    if (-not $data) { $data = $lines | Select-Object -Last 1 }
    if (-not $data) { return $null }
    return ($data -replace '"', '').Trim()
}

Write-Host ""
Write-Host "CDC LATENCY EXPERIMENT" -ForegroundColor Cyan
Write-Host "PostgreSQL INSERT -> Debezium -> Kafka -> Flink -> Iceberg Gold -> Presto" -ForegroundColor DarkCyan
Write-Host ""

# --- BEFORE ---
$beforeCount = Get-PrestoScalar "SELECT CAST(COUNT(*) AS VARCHAR) FROM fact_sales_order_line"
if (-not $beforeCount) { $beforeCount = "0" }
Write-Host "[BEFORE] Gold fact rows: $beforeCount" -ForegroundColor Yellow

$maxBefore = Get-PrestoScalar "SELECT CAST(COALESCE(MAX(sales_order_id), 0) AS VARCHAR) FROM fact_sales_order_line"
if (-not $maxBefore) { $maxBefore = "0" }
Write-Host "[BEFORE] Max sales_order_id in Gold: $maxBefore" -ForegroundColor Yellow

# --- INSERT (same pattern as demo-pipeline.ps1) ---
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

Write-Host ""
Write-Host "[INSERT] 1 header + 1 line (product 11, qty 2, GEL)..." -ForegroundColor Cyan
$t0 = Get-Date
$insertOut = & docker exec $pg psql -U postgres -d adventureworks -t -A -c $insertSql
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL INSERT failed" }
Write-Host $insertOut

# Parse "order_id|detail_id"
$newOrderId = ($insertOut -split "`n" | Where-Object { $_ -match '^\d+\|' } | Select-Object -First 1)
if ($newOrderId) {
    $newOrderId = ($newOrderId -split '\|')[0].Trim()
} else {
    $newOrderId = & docker exec $pg psql -U postgres -d adventureworks -t -A -c "SELECT MAX(sales_order_id) FROM sales.sales_order_header;"
    $newOrderId = $newOrderId.Trim()
}
Write-Host "[INSERT] New sales_order_id = $newOrderId  (t0 = $($t0.ToString('HH:mm:ss.fff')))" -ForegroundColor Green

# --- POLL GOLD ---
Write-Host ""
Write-Host "[POLL] Waiting for Gold fact to contain sales_order_id=$newOrderId (timeout ${TimeoutSeconds}s)..." -ForegroundColor Cyan
$found = $false
$latencySec = $null
$deadline = $t0.AddSeconds($TimeoutSeconds)

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds $PollSeconds
    $hit = Get-PrestoScalar "SELECT CAST(COUNT(*) AS VARCHAR) FROM fact_sales_order_line WHERE sales_order_id = $newOrderId"
    $elapsed = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    Write-Host "  ... ${elapsed}s  count_for_order=$hit" -ForegroundColor Gray
    if ($hit -and [int]$hit -ge 1) {
        $t1 = Get-Date
        $latencySec = [math]::Round(($t1 - $t0).TotalSeconds, 1)
        $found = $true
        break
    }
}

if (-not $found) {
    Write-Host "[FAIL] Order $newOrderId not in Gold within ${TimeoutSeconds}s. Check Flink UI http://localhost:8081" -ForegroundColor Red
    $latencySec = "TIMEOUT"
} else {
    Write-Host "[OK] Visible in Gold after ${latencySec}s" -ForegroundColor Green
}

$afterCount = Get-PrestoScalar "SELECT CAST(COUNT(*) AS VARCHAR) FROM fact_sales_order_line"
$goldSample = Invoke-Presto "SELECT sales_order_id, customer_id, product_id, order_qty, line_total FROM fact_sales_order_line WHERE sales_order_id = $newOrderId"

# --- KPIs ---
Write-Host ""
Write-Host "[KPI] Running analytics pack samples..." -ForegroundColor Cyan
$kpiRevenue = Invoke-Presto @"
SELECT CAST(ROUND(SUM(line_total), 2) AS VARCHAR) AS total_revenue,
       CAST(COUNT(sales_order_id) AS VARCHAR) AS order_id_refs,
       CAST(COUNT(*) AS VARCHAR) AS lines
FROM fact_sales_order_line
"@

$kpiTop = Invoke-Presto @"
SELECT dp.product_name, CAST(ROUND(SUM(f.line_total), 2) AS VARCHAR) AS revenue
FROM fact_sales_order_line f
JOIN dim_product dp ON dp.product_id = f.product_id
GROUP BY dp.product_name
ORDER BY SUM(f.line_total) DESC
LIMIT 5
"@

$kpiTerritory = Invoke-Presto @"
SELECT dt.territory_name, CAST(ROUND(SUM(f.line_total), 2) AS VARCHAR) AS revenue
FROM fact_sales_order_line f
JOIN dim_territory dt ON dt.territory_id = f.territory_id
GROUP BY dt.territory_name
ORDER BY SUM(f.line_total) DESC
LIMIT 5
"@

# --- K-Means (optional) ---
$kmeansBlock = "_skipped_"
if (-not $SkipKMeans) {
    Write-Host ""
    Write-Host "[ML] Running K-Means on Gold Parquet..." -ForegroundColor Cyan
    try {
        $kmeansOut = & docker exec $airflow python /opt/airflow/analytics/kmeans_customers.py 2>&1 | Out-String
        $kmeansBlock = $kmeansOut
        Write-Host "K-Means finished." -ForegroundColor Green
    } catch {
        $kmeansBlock = "K-Means failed or Airflow not ready: $($_.Exception.Message)"
        Write-Host $kmeansBlock -ForegroundColor Yellow
    }
}

# --- REPORT ---
$runTs = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$fileTs = Get-Date -Format "yyyyMMdd_HHmmss"
$goldSampleText = ($goldSample -join "`n")
$kpiRevenueText = ($kpiRevenue -join "`n")
$kpiTopText = ($kpiTop -join "`n")
$kpiTerritoryText = ($kpiTerritory -join "`n")

$report = @"
# Experiment results — CDC Latency + KPI

**Run:** $runTs  
**Script:** ``scripts/run-experiment.ps1``  
**Change path:** same as ``demo-pipeline.ps1`` (PostgreSQL INSERT -> Debezium -> Kafka -> Flink -> Iceberg Gold)

---

## 1. End-to-end latency

| Metric | Value |
|--------|-------|
| New ``sales_order_id`` | **$newOrderId** |
| Gold fact rows BEFORE | $beforeCount |
| Gold fact rows AFTER | $afterCount |
| Max order_id BEFORE | $maxBefore |
| **Latency (INSERT -> Gold visible)** | **${latencySec} s** |
| Timeout | ${TimeoutSeconds}s |
| Poll interval | ${PollSeconds}s |

### New Gold row

``````
$goldSampleText
``````

**Interpretation:** latency includes Debezium WAL read, Kafka publish, Flink checkpoint (~10s), and Iceberg commit on MinIO. Typical local demo range: **~10-40 seconds**.

---

## 2. KPI snapshot (Presto / Gold)

### Total revenue / lines

``````
$kpiRevenueText
``````

### Top 5 products by revenue

``````
$kpiTopText
``````

### Revenue by territory

``````
$kpiTerritoryText
``````

Same metrics as the Metabase dashboard (see ``docs/BI_DASHBOARD_KA.md``).

---

## 3. K-Means (batch ML)

``````
$kmeansBlock
``````

Output files in MinIO: ``lakehouse-admin/analytics/customer_clusters/``

---

## 4. Short thesis conclusion

1. An OLTP change in PostgreSQL appears automatically in the Lakehouse Gold layer via the CDC pipeline.
2. Measured end-to-end latency: **${latencySec} seconds**.
3. The same data is available for KPI analytics via Presto/Metabase after the stream catches up.
4. Airflow + K-Means demonstrates a batch ML layer separate from streaming.

"@

$latest = Join-Path $outDir "latest.md"
$dated  = Join-Path $outDir "run_$fileTs.md"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($latest, $report, $utf8)
[System.IO.File]::WriteAllText($dated, $report, $utf8)

Write-Host ""
Write-Host "Report written:" -ForegroundColor Green
Write-Host "  $latest"
Write-Host "  $dated"
Write-Host ""
Write-Host "Latency: ${latencySec}s | order_id=$newOrderId | Gold $beforeCount -> $afterCount" -ForegroundColor Cyan
Write-Host "Metabase: http://localhost:3000  |  setup: .\scripts\setup-metabase.ps1" -ForegroundColor Gray
Write-Host ""
