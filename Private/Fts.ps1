# PSSnips — Full-text search index helpers.
function script:SearchSnipContent {
    # Returns $true if the snippet file body contains $SearchString (case-insensitive).
    # Falls back to direct file read when a FTS cache entry is not yet present.
    param([string]$Name, [string]$SearchString)
    $fts = script:LoadFts
    if ($fts.ContainsKey($Name)) {
        return $fts[$Name] -match [regex]::Escape($SearchString)
    }
    # fallback: read file directly (first time or cache miss)
    $snipPath = script:FindFile -Name $Name
    if (-not $snipPath -or -not (Test-Path $snipPath)) { return $false }
    try { return (Select-String -Path $snipPath -Pattern ([regex]::Escape($SearchString)) -Quiet) }
    catch { return $false }
}

function script:LoadFts {
    if ($null -ne $script:FtsCache) { return $script:FtsCache }
    if (Test-Path $script:FtsCacheFile) {
        try {
            $script:FtsCache = (Get-Content $script:FtsCacheFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable)
        } catch { $script:FtsCache = @{} }
    } else { $script:FtsCache = @{} }
    return $script:FtsCache
}

function script:UpdateFts {
    param([string]$Name)
    $fts  = script:LoadFts
    $file = script:FindFile -Name $Name
    if ($file -and (Test-Path $file)) {
        $fts[$Name] = (Get-Content $file -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) ?? ''
    } else {
        $fts.Remove($Name)
    }
    $fts | ConvertTo-Json -Depth 3 | Set-Content $script:FtsCacheFile -Encoding UTF8
    $script:FtsCache = $fts
}

function script:RemoveFts {
    param([string]$Name)
    $fts = script:LoadFts
    $fts.Remove($Name)
    $fts | ConvertTo-Json -Depth 3 | Set-Content $script:FtsCacheFile -Encoding UTF8
    $script:FtsCache = $fts
}

