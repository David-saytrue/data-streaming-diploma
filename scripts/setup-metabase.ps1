# Metabase setup helper — open UI and print Presto connection steps
# Usage: .\scripts\setup-metabase.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

Write-Host "Waiting for Metabase at http://localhost:3000 ..." -ForegroundColor Cyan
$ok = $false
for ($i = 1; $i -le 60; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:3000/api/health" -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch {
        Start-Sleep -Seconds 5
    }
    Write-Host "  attempt $i/60 ..." -ForegroundColor Gray
}

if (-not $ok) {
    Write-Host "Metabase not ready. Run: docker compose up -d metabase" -ForegroundColor Red
    exit 1
}

Write-Host "Metabase is UP: http://localhost:3000" -ForegroundColor Green
Write-Host ""
Write-Host "=== First-time setup (browser) ===" -ForegroundColor Cyan
Write-Host "1. Open http://localhost:3000"
Write-Host "2. Create admin user (any email/password for local demo)"
Write-Host "3. Add database:"
Write-Host ""
Write-Host "   Database type : Presto"
Write-Host "   Display name : AdventureWorks Lakehouse"
Write-Host "   Host         : presto"
Write-Host "   Port         : 8080"
Write-Host "   Catalog      : iceberg"
Write-Host "   Schema       : gold"
Write-Host "   User         : (leave empty or presto)"
Write-Host "   SSL          : OFF"
Write-Host ""
Write-Host "=== Recommended dashboard cards (SQL) ===" -ForegroundColor Cyan
Write-Host "See docs/BI_DASHBOARD_KA.md for copy-paste questions."
Write-Host ""
Write-Host "After CDC experiment, refresh dashboard - new orders appear automatically." -ForegroundColor Yellow
