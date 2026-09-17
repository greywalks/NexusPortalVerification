[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$BaseUrl)

$ErrorActionPreference = "Stop"
$BaseUrl = $BaseUrl.TrimEnd("/")

function Get-Status([string]$Path) {
    try {
        return (Invoke-WebRequest -Uri "$BaseUrl$Path" -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop).StatusCode
    }
    catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        throw
    }
}

$Health = Invoke-RestMethod -Uri "$BaseUrl/index.cfm/healthz"
if (-not $Health.ok) { throw "/index.cfm/healthz did not report a healthy application." }
Write-Host "[OK] /index.cfm/healthz"

$Login = Invoke-WebRequest -Uri "$BaseUrl/index.cfm/login" -UseBasicParsing
if ($Login.Content -notmatch "Sign in") { throw "/index.cfm/login did not render the sign-in page." }
Write-Host "[OK] /index.cfm/login"

$Expected = @{
    "/static/css/app.css" = @(200)
    "/Application.cfc" = @(403,404)
    "/data/logicore.mv.db" = @(403,404)
    "/config/serial_rules.json" = @(403,404)
    "/services/AuthService.cfc" = @(403,404)
    "/tests/billing_parity.cfm" = @(403,404)
    "/index.cfm/tests/billing_parity.cfm" = @(403,404)
    "/views/portal.html" = @(403,404)
    "/.github/workflows/lucee-smoke-test.yml" = @(403,404)
}
foreach ($Path in $Expected.Keys) {
    $Status = Get-Status $Path
    if ($Expected[$Path] -notcontains $Status) { throw "$Path returned $Status; expected $($Expected[$Path] -join ' or ')." }
    Write-Host "[OK] $Path -> $Status"
}

Write-Host "Deployment checks passed for $BaseUrl"

