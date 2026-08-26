# Start full pipeline: Docker + Debezium + Flink + Demo + K-Means + Experiment
# Usage: .\start-all.ps1

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "=== 1/6 Docker compose up ===" -ForegroundColor Cyan
docker compose up -d
Write-Host "Waiting 60 sec for services..." -ForegroundColor Gray
Start-Sleep -Seconds 60
docker compose ps

Write-Host "`n=== 2/6 Debezium connector ===" -ForegroundColor Cyan
$json = Get-Content register-connector.json -Raw
try {
    Invoke-RestMethod -Uri "http://localhost:8083/connectors" -Method Post -Body $json -ContentType "application/json" | Out-Null
    Write-Host "Connector created." -ForegroundColor Green
} catch {
    Write-Host "Connector may already exist - continuing." -ForegroundColor Yellow
}

Write-Host "`n=== 3/6 Flink job ===" -ForegroundColor Cyan
docker exec data-streaming-diploma-jobmanager-1 /opt/flink/bin/sql-client.sh -f /opt/flink/flink_job.sql

Write-Host "`n=== 4/6 dim_date + CDC demo ===" -ForegroundColor Cyan
docker exec -i data-streaming-diploma-presto-1 /opt/presto-cli --catalog iceberg --schema gold -f /opt/presto-server/etc/sql/dim_date.sql
powershell -NoProfile -File ".\demo-pipeline.ps1" -SkipInfra

Write-Host "`n=== 5/6 K-Means (wait for Airflow ~90 sec if first start) ===" -ForegroundColor Cyan
Start-Sleep -Seconds 30
docker exec data-streaming-diploma-airflow-1 python /opt/airflow/analytics/kmeans_customers.py

Write-Host "`n=== 6/6 CDC latency experiment + report ===" -ForegroundColor Cyan
powershell -NoProfile -File ".\scripts\run-experiment.ps1" -SkipKMeans

Write-Host "`n=== DONE ===" -ForegroundColor Green
Write-Host "Flink:    http://localhost:8081"
Write-Host "MinIO:    http://localhost:9001  (admin / adminpassword)"
Write-Host "Airflow:  http://localhost:8085  (admin / admin)"
Write-Host "Presto:   http://localhost:8080"
Write-Host "Metabase: http://localhost:3000  (setup: .\scripts\setup-metabase.ps1)"
Write-Host "Report:   docs\experiment-results\latest.md"
