# Deploys the WoWTCG addon from this repo into the WoW AddOns folders.
# Usage (from anywhere):  powershell -ExecutionPolicy Bypass -File deploy.ps1
$ErrorActionPreference = 'Stop'

$repo = $PSScriptRoot
$targets = @(
    'F:\World of Warcraft\_anniversary_\Interface\AddOns\WoWTCG',
    'F:\World of Warcraft\_classic_era_\Interface\AddOns\WoWTCG'
)

# Dev-only folders that must not ship into the game client.
$excludeDirs = @('.git', '.claude', 'docs', 'tests') | ForEach-Object { Join-Path $repo $_ }
$excludeFiles = @('.gitignore', 'deploy.ps1')

foreach ($target in $targets) {
    robocopy $repo $target /MIR /XD $excludeDirs /XF $excludeFiles /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $target (exit $LASTEXITCODE)" }
    if (-not (Test-Path (Join-Path $target 'WoWTCG.toc'))) { throw "deploy verification failed: no TOC in $target" }
    Write-Host "Deployed -> $target"
}
Write-Host 'Done. /reload (or restart the client) to pick up changes.'
