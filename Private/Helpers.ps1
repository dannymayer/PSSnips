# PSSnips — Miscellaneous helpers: content hashing and version history.
function script:GetContentHash {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    return ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}


function script:SaveVersion {
    param([string]$Name, [string]$FilePath)
    if (-not $FilePath -or -not (Test-Path $FilePath)) { return }
    $cfg     = script:LoadCfg
    $maxHist = if ($cfg.ContainsKey('MaxHistory')) { [int]$cfg['MaxHistory'] } else { 10 }
    $histDir = Join-Path (Join-Path $script:Home 'history') $Name
    if (-not (Test-Path $histDir)) { New-Item -ItemType Directory -Path $histDir -Force | Out-Null }
    $ts      = Get-Date -Format 'yyyyMMddHHmmss'
    $ext     = [System.IO.Path]::GetExtension($FilePath)
    $dest    = Join-Path $histDir "$ts$ext"
    Copy-Item -Path $FilePath -Destination $dest -Force
    # Prune oldest versions beyond MaxHistory
    $versions = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue | Sort-Object Name)
    while ($versions.Count -gt $maxHist) {
        Remove-Item $versions[0].FullName -Force -ErrorAction SilentlyContinue
        $versions = @($versions | Select-Object -Skip 1)
    }
}
