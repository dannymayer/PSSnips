# PSSnips — Console output helpers (banner and status indicators).
function script:Out-Banner {
    $lines = @(
"   ___  __  __       _           ",
"  / _ \/ _\/ _\_ __ (_)_ __  ___ ",
" / /_)/\ \ \ \| '_ \| | '_ \/ __|",
"/ ___/ _\ \_\ \ | | | | |_) \__ \",
"\/     \__/\__/_| |_|_| .__/|___/",
"                     |_|         "
    )
    Write-Host ""
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Cyan }
    Write-Host "  PowerShell Snippet Manager  v1.0`n" -ForegroundColor DarkCyan
}

function script:Out-OK   { param([string]$m) Write-Host "  [+] $m" -ForegroundColor Green }
function script:Out-Err  { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Red }
function script:Out-Warn { param([string]$m) Write-Host "  [~] $m" -ForegroundColor Yellow }
function script:Out-Info { param([string]$m) Write-Host "  [i] $m" -ForegroundColor DarkCyan }

