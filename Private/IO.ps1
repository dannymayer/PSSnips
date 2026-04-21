# PSSnips — File-system and editor helpers.
function script:EnsureDirs {
    $cfg = script:LoadCfg
    foreach ($d in @($script:Home, $cfg.SnippetsDir, (Join-Path $script:Home 'history'))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}


function script:FindFile {
    param([string]$Name)
    $cfg = script:LoadCfg
    $dir = $cfg.SnippetsDir
    # Exact match first (name.ext)
    $hits = @(Get-ChildItem $dir -Filter "$Name.*" -File -ErrorAction SilentlyContinue)
    if ($hits.Count -gt 0) { return $hits[0].FullName }
    return $null
}

function script:GetEditor {
    param([string]$Override = '')
    if ($Override -and (Get-Command $Override -ErrorAction SilentlyContinue)) { return $Override }
    $cfg = script:LoadCfg
    # @() ensures $cfg.Editor is always treated as an array before concatenation,
    # preventing issues when Editor is stored as a bare string rather than an array.
    foreach ($ed in (@($cfg.Editor) + $cfg.EditorFallbacks)) {
        if (Get-Command $ed -ErrorAction SilentlyContinue) { return $ed }
    }
    return 'notepad'  # ultimate fallback: notepad is always present on Windows
}

function script:LangColor {
    param([string]$ext)
    $e = $ext.TrimStart('.').ToLower()
    if ($script:LangColor.ContainsKey($e)) { return $script:LangColor[$e] }
    return 'White'
}

