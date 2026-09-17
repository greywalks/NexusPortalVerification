[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$libDirectory = Join-Path $projectRoot "lib"
$h2Jar = Join-Path $libDirectory "h2-2.1.214.jar"
$h2Uri = "https://repo.maven.apache.org/maven2/com/h2database/h2/2.1.214/h2-2.1.214.jar"
$expectedSha256 = "d623cdc0f61d218cf549a8d09f1c391ff91096116b22e2475475fce4fbe72bd0"

New-Item -ItemType Directory -Path $libDirectory -Force | Out-Null

if (-not (Test-Path $h2Jar)) {
    Write-Host "Downloading the pinned H2 database driver..."
    Invoke-WebRequest -Uri $h2Uri -OutFile $h2Jar
}

$actualSha256 = (Get-FileHash -Path $h2Jar -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $expectedSha256) {
    Remove-Item -Path $h2Jar -Force
    throw "H2 driver checksum validation failed. The downloaded file was removed."
}

Write-Host "[OK] H2 database driver is installed and verified:"
Write-Host "     $h2Jar"
