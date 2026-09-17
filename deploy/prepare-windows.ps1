[CmdletBinding()]
param(
    [string]$AppRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$ServiceAccount = ""
)

$ErrorActionPreference = "Stop"
$H2Version = "2.1.214"
$H2Sha256 = "d623cdc0f61d218cf549a8d09f1c391ff91096116b22e2475475fce4fbe72bd0"
$H2Url = "https://repo.maven.apache.org/maven2/com/h2database/h2/$H2Version/h2-$H2Version.jar"
$AppRoot = (Resolve-Path $AppRoot).Path

if (-not (Test-Path (Join-Path $AppRoot "Application.cfc")) -or -not (Test-Path (Join-Path $AppRoot "index.cfm"))) {
    throw "Application.cfc and index.cfm were not found in $AppRoot"
}

$Lib = Join-Path $AppRoot "lib"
$H2Jar = Join-Path $Lib "h2-$H2Version.jar"
New-Item -ItemType Directory -Path $Lib -Force | Out-Null

$InstallH2 = -not (Test-Path $H2Jar)
if (-not $InstallH2) {
    $InstallH2 = (Get-FileHash -Path $H2Jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $H2Sha256
}
if ($InstallH2) {
    $TempJar = Join-Path ([System.IO.Path]::GetTempPath()) ("h2-" + [guid]::NewGuid().ToString("N") + ".jar")
    try {
        Invoke-WebRequest -Uri $H2Url -OutFile $TempJar
        $ActualHash = (Get-FileHash -Path $TempJar -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualHash -ne $H2Sha256) { throw "H2 checksum verification failed." }
        Move-Item -Path $TempJar -Destination $H2Jar -Force
    }
    finally {
        if (Test-Path $TempJar) { Remove-Item $TempJar -Force }
    }
}

$WritablePaths = @(
    (Join-Path $AppRoot "data"),
    (Join-Path $AppRoot "data\training_signoffs"),
    (Join-Path $AppRoot "uploads"),
    (Join-Path $AppRoot "outputs"),
    (Join-Path $AppRoot "outputs\.access"),
    (Join-Path $AppRoot "config")
)
foreach ($Path in $WritablePaths) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }

if ($ServiceAccount) {
    foreach ($Path in $WritablePaths) {
        & icacls.exe $Path /grant "${ServiceAccount}:(OI)(CI)M" /T /C | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to grant Modify permission on $Path to $ServiceAccount" }
    }
}
else {
    Write-Warning "No -ServiceAccount was provided. Grant the Lucee/Tomcat Windows service identity Modify permission to data, uploads, outputs, and config before starting the site."
}

Write-Host "[OK] H2 driver verified: $H2Jar"
Write-Host "[OK] Runtime directories exist."
Write-Host "Configure Apache from deploy\apache\ussi-nexus-vhost.conf.example, restart Lucee/Tomcat, reload Apache, and run deploy\check-deployment.ps1."

