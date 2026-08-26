# Configure Metabase: admin + Presto + dashboard cards
# Usage: .\scripts\configure-metabase.ps1

$ErrorActionPreference = "Stop"
$base = "http://localhost:3000"

function Invoke-Mb {
    param(
        [string]$Method,
        [string]$Path,
        [hashtable]$Headers = @{},
        $Body = $null
    )
    $uri = "$base$Path"
    $params = @{
        Uri = $uri
        Method = $Method
        Headers = $Headers
        ContentType = "application/json"
    }
    if ($null -ne $Body) {
        if ($Body -is [string]) { $params.Body = $Body }
        else { $params.Body = ($Body | ConvertTo-Json -Depth 8) }
    }
    return Invoke-RestMethod @params
}

Write-Host "=== Metabase configure ===" -ForegroundColor Cyan

# --- Session: setup or login ---
$props = Invoke-Mb -Method Get -Path "/api/session/properties"
$session = $null

if (-not $props.'has-user-setup') {
    $token = $props.'setup-token'
    if (-not $token) { throw "No setup-token" }
    Write-Host "Running first-time setup..."
    $setupResp = Invoke-Mb -Method Post -Path "/api/setup" -Body @{
        token = $token
        user = @{
            first_name = "Admin"
            last_name  = "Diploma"
            email      = "admin@adventureworks.local"
            password   = "Admin123!"
        }
        prefs = @{
            site_name = "AdventureWorks Lakehouse"
            site_locale = "en"
            allow_tracking = $false
        }
    }
    if ($setupResp -is [string]) { $session = $setupResp }
    elseif ($setupResp.id) { $session = $setupResp.id }
}

if (-not $session) {
    Write-Host "Logging in..."
    $login = Invoke-Mb -Method Post -Path "/api/session" -Body @{
        username = "admin@adventureworks.local"
        password = "Admin123!"
    }
    $session = $login.id
}

Write-Host "Session OK"
$h = @{ "X-Metabase-Session" = "$session" }

# --- Presto database ---
$existing = Invoke-Mb -Method Get -Path "/api/database" -Headers $h
$dbId = $null
foreach ($d in @($existing.data)) {
    if ($d.name -eq "AdventureWorks Lakehouse") { $dbId = $d.id; break }
}
# older API returns array directly
if (-not $dbId) {
    foreach ($d in @($existing)) {
        if ($d.name -eq "AdventureWorks Lakehouse") { $dbId = $d.id; break }
    }
}

$dbDetails = [ordered]@{
    host = "presto"
    port = 8080
    catalog = "iceberg"
    schema = "gold"
    user = "presto"
    ssl = $false
}
$dbDetails["advanced-options"] = $false

if ($dbId) {
    Write-Host "Database already exists id=$dbId"
} else {
    $engine = "presto-jdbc"
    Write-Host "Creating Presto DB (engine=$engine)..."
    try {
        $db = Invoke-Mb -Method Post -Path "/api/database" -Headers $h -Body @{
            name = "AdventureWorks Lakehouse"
            engine = $engine
            details = $dbDetails
            is_full_sync = $true
            auto_run_queries = $true
        }
        $dbId = $db.id
    } catch {
        Write-Host "presto-jdbc failed: $($_.ErrorDetails.Message)"
        Write-Host "Trying engine=presto..."
        $db = Invoke-Mb -Method Post -Path "/api/database" -Headers $h -Body @{
            name = "AdventureWorks Lakehouse"
            engine = "presto"
            details = $dbDetails
            is_full_sync = $true
            auto_run_queries = $true
        }
        $dbId = $db.id
    }
    Write-Host "Created database id=$dbId"
}

Invoke-Mb -Method Post -Path "/api/database/$dbId/sync_schema" -Headers $h | Out-Null
Write-Host "Syncing schema (20s)..."
Start-Sleep -Seconds 20

# --- Collection for diploma dashboard ---
$collections = Invoke-Mb -Method Get -Path "/api/collection" -Headers $h
$collId = $null
foreach ($c in @($collections)) {
    if ($c.name -eq "Diploma") { $collId = $c.id; break }
}
if (-not $collId) {
    $coll = Invoke-Mb -Method Post -Path "/api/collection" -Headers $h -Body @{
        name = "Diploma"
        color = "#509EE3"
    }
    $collId = $coll.id
}
Write-Host "Collection id=$collId"

function New-NativeCard {
    param(
        [string]$Name,
        [string]$Sql,
        [string]$Display,
        [int]$CollectionId,
        [int]$DatabaseId,
        [hashtable]$Headers,
        [hashtable]$Viz = @{}
    )
    $payload = @{
        name = $Name
        dataset_query = @{
            type = "native"
            native = @{ query = $Sql }
            database = $DatabaseId
        }
        display = $Display
        visualization_settings = $Viz
        collection_id = $CollectionId
    }
    return Invoke-Mb -Method Post -Path "/api/card" -Headers $Headers -Body $payload
}

# Avoid COUNT(DISTINCT) warning noise; keep queries simple
$sqlKpi = @"
SELECT
  ROUND(SUM(line_total), 2) AS total_revenue,
  COUNT(sales_order_id) AS order_lines,
  COUNT(*) AS rows
FROM fact_sales_order_line
"@

$sqlByDay = @"
SELECT
  CAST(order_ts AS DATE) AS order_day,
  ROUND(SUM(line_total), 2) AS revenue,
  COUNT(*) AS lines
FROM fact_sales_order_line
GROUP BY 1
ORDER BY 1
"@

$sqlTopProducts = @"
SELECT
  dp.product_name,
  ROUND(SUM(f.line_total), 2) AS revenue
FROM fact_sales_order_line f
JOIN dim_product dp ON dp.product_id = f.product_id
GROUP BY dp.product_name
ORDER BY revenue DESC
LIMIT 10
"@

$sqlTerritory = @"
SELECT
  dt.territory_name,
  ROUND(SUM(f.line_total), 2) AS revenue
FROM fact_sales_order_line f
JOIN dim_territory dt ON dt.territory_id = f.territory_id
GROUP BY dt.territory_name
ORDER BY revenue DESC
"@

$sqlRecent = @"
SELECT
  sales_order_id,
  order_ts,
  customer_id,
  product_id,
  order_qty,
  line_total
FROM fact_sales_order_line
ORDER BY order_ts DESC NULLS LAST
LIMIT 15
"@

Write-Host "Creating cards..."
$cardKpi = New-NativeCard -Name "KPI Total Revenue" -Sql $sqlKpi -Display "scalar" -CollectionId $collId -DatabaseId $dbId -Headers $h -Viz @{
    "scalar.field" = "total_revenue"
}
$cardDay = New-NativeCard -Name "Revenue by Day" -Sql $sqlByDay -Display "line" -CollectionId $collId -DatabaseId $dbId -Headers $h
$cardTop = New-NativeCard -Name "Top Products" -Sql $sqlTopProducts -Display "bar" -CollectionId $collId -DatabaseId $dbId -Headers $h
$cardTerr = New-NativeCard -Name "Revenue by Territory" -Sql $sqlTerritory -Display "row" -CollectionId $collId -DatabaseId $dbId -Headers $h
$cardRecent = New-NativeCard -Name "Recent Orders (CDC)" -Sql $sqlRecent -Display "table" -CollectionId $collId -DatabaseId $dbId -Headers $h

Write-Host "Cards: $($cardKpi.id), $($cardDay.id), $($cardTop.id), $($cardTerr.id), $($cardRecent.id)"

# --- Dashboard ---
$dashList = Invoke-Mb -Method Get -Path "/api/dashboard" -Headers $h
$dashId = $null
foreach ($d in @($dashList)) {
    if ($d.name -eq "AdventureWorks Sales") { $dashId = $d.id; break }
}
if (-not $dashId) {
    $dash = Invoke-Mb -Method Post -Path "/api/dashboard" -Headers $h -Body @{
        name = "AdventureWorks Sales"
        description = "CDC Lakehouse Gold KPIs - diploma demo"
        collection_id = $collId
    }
    $dashId = $dash.id
}
Write-Host "Dashboard id=$dashId"

# Attach cards via PUT /api/dashboard/:id (dashcards) — Metabase 0.49+
$dashcards = @(
    @{ id = -1; card_id = $cardKpi.id;    row = 0;  col = 0;  size_x = 6;  size_y = 3; parameter_mappings = @(); visualization_settings = @{} }
    @{ id = -2; card_id = $cardDay.id;    row = 0;  col = 6;  size_x = 12; size_y = 6; parameter_mappings = @(); visualization_settings = @{} }
    @{ id = -3; card_id = $cardTop.id;    row = 6;  col = 0;  size_x = 9;  size_y = 6; parameter_mappings = @(); visualization_settings = @{} }
    @{ id = -4; card_id = $cardTerr.id;   row = 6;  col = 9;  size_x = 9;  size_y = 6; parameter_mappings = @(); visualization_settings = @{} }
    @{ id = -5; card_id = $cardRecent.id; row = 12; col = 0;  size_x = 18; size_y = 6; parameter_mappings = @(); visualization_settings = @{} }
)
Invoke-Mb -Method Put -Path "/api/dashboard/$dashId" -Headers $h -Body @{
    name = "AdventureWorks Sales"
    description = "CDC Lakehouse Gold KPIs - diploma demo"
    collection_id = $collId
    dashcards = $dashcards
    parameters = @()
} | Out-Null
Write-Host "Dashboard cards attached: $($dashcards.Count)"

Write-Host ""
Write-Host "DONE" -ForegroundColor Green
Write-Host "Open:  http://localhost:3000"
Write-Host "Login: admin@adventureworks.local / Admin123!"
Write-Host "Dash:  http://localhost:3000/dashboard/$dashId"
Write-Host "Coll:  http://localhost:3000/collection/$collId"
