# PSSnips — Config/index persistence, file locking, and environment initialisation.
function script:LoadCfg {
    if (-not $script:CfgDirty -and $null -ne $script:CfgCache) { return $script:CfgCache }

    # Start with defaults
    $cfg = @{}
    $script:Defaults.GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value }

    # Layer 1: user config (~/.pssnips/config.json)
    if (Test-Path $script:CfgFile) {
        try {
            $raw = Get-Content $script:CfgFile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) {
                $loaded = $raw | ConvertFrom-Json -AsHashtable
                foreach ($k in $loaded.Keys) { $cfg[$k] = $loaded[$k] }
            }
        } catch { Write-Verbose "LoadCfg: user config error — $($_.Exception.Message)" }
    }

    # Layer 2: workspace config (.pssnips/config.json in cwd, or $env:PSSNIPS_WORKSPACE)
    if ($script:WorkspaceCfgFile -and (Test-Path $script:WorkspaceCfgFile)) {
        try {
            $raw = Get-Content $script:WorkspaceCfgFile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) {
                $wsLoaded = $raw | ConvertFrom-Json -AsHashtable
                foreach ($k in $wsLoaded.Keys) { $cfg[$k] = $wsLoaded[$k] }
            }
        } catch { Write-Verbose "LoadCfg: workspace config error — $($_.Exception.Message)" }
    }

    # Layer 3: environment variables (highest priority, override everything)
    foreach ($envKey in $script:EnvVarMap.Keys) {
        $envVal = [System.Environment]::GetEnvironmentVariable($envKey)
        if ($envVal) { $cfg[$script:EnvVarMap[$envKey]] = $envVal }
    }

    $script:CfgCache = $cfg
    $script:CfgDirty = $false
    return $cfg
}

function script:SaveCfg {
    <#
    .SYNOPSIS
        Writes config.json atomically using a temp-file + rename pattern and an
        advisory .lock file to prevent concurrent overwrites.
    .NOTES
        Acquires the target config file's .lock before writing.
        On lock timeout a Write-Warning is emitted and the write proceeds anyway so
        the caller is never left without a config. The temp file is always cleaned up
        even on error via try/finally.
        Use -Scope Workspace to write to the workspace config (.pssnips/config.json in
        the current directory, or the path set in $env:PSSNIPS_WORKSPACE).
    #>
    param(
        [hashtable]$Cfg,
        [string]$Scope = 'User'
    )
    $targetFile = if ($Scope -eq 'Workspace') {
        if (-not $script:WorkspaceCfgFile) {
            Write-Warning "Workspace config path not initialised. Call script:InitEnv first."
            return
        }
        $wsDir = Split-Path $script:WorkspaceCfgFile -Parent
        if (-not (Test-Path $wsDir)) { New-Item -ItemType Directory -Path $wsDir -Force | Out-Null }
        $script:WorkspaceCfgFile
    } else {
        $script:CfgFile
    }
    $lockFile = "$targetFile.lock"
    $lock = script:AcquireLock -LockFile $lockFile
    try {
        $tmp = "$targetFile.tmp"
        $Cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $targetFile -Force
        if ($Scope -eq 'User') {
            $script:CfgCache = $Cfg
            $script:CfgDirty = $false
        }
    } finally {
        script:ReleaseLock -Stream $lock -LockFile $lockFile
        if (Test-Path "$targetFile.tmp") { Remove-Item "$targetFile.tmp" -ErrorAction SilentlyContinue }
    }
}

function script:LoadIdx {
    if (-not $script:IdxDirty -and $null -ne $script:IdxCache) {
        return $script:IdxCache
    }
    if (Test-Path $script:IdxFile) {
        try {
            $raw = Get-Content $script:IdxFile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) {
                $idx = $raw | ConvertFrom-Json -AsHashtable  # -AsHashtable preserves nested hashtables for index key access
                if (-not $idx.ContainsKey('snippets')) { $idx['snippets'] = @{} }
                $script:IdxCache = $idx
                $script:IdxDirty = $false
                return $idx
            }
        } catch { Write-Verbose "LoadIdx: reinitialising index — $($_.Exception.Message)" }
    }
    $idx = @{ snippets = @{} }
    $script:IdxCache = $idx
    $script:IdxDirty = $false
    return $idx
}

function script:SaveIdx {
    <#
    .SYNOPSIS
        Writes index.json atomically using a temp-file + rename pattern and an
        advisory .lock file to prevent concurrent overwrites.
    .NOTES
        Acquires $script:IdxFile.lock (exclusive FileShare.None) before writing.
        On lock timeout a Write-Warning is emitted and the write proceeds anyway so
        the caller is never blocked indefinitely. The temp file is always cleaned up
        even on error via try/finally.
        For full read-modify-write atomicity, wrap the load+modify+save sequence in
        script:WithIdxLock { ... } at the call site.
    #>
    param([hashtable]$Idx)
    $lockFile = "$script:IdxFile.lock"
    $lock = script:AcquireLock -LockFile $lockFile
    try {
        $tmp = "$script:IdxFile.tmp"
        $Idx | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $script:IdxFile -Force
        $script:IdxCache = $Idx
        $script:IdxDirty = $false
        $script:CompleterCache = $null
    } finally {
        script:ReleaseLock -Stream $lock -LockFile $lockFile
        if (Test-Path "$script:IdxFile.tmp") { Remove-Item "$script:IdxFile.tmp" -ErrorAction SilentlyContinue }
    }
}


function script:AcquireLock {
    <#
    .SYNOPSIS
        Opens a .lock file with exclusive access. Returns a FileStream on success,
        or $null after TimeoutMs if the file is held by another process.
    .NOTES
        Works on local NTFS and UNC paths. Callers must pass the stream to
        script:ReleaseLock in a finally block.
    #>
    param(
        [string]$LockFile,
        [int]$TimeoutMs = $script:LockTimeoutMs,
        [int]$RetryMs   = 50
    )
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        try {
            $stream = [System.IO.File]::Open(
                $LockFile,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            return $stream
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds $RetryMs
        }
    }
    Write-Warning "PSSnips: could not acquire lock on '$LockFile' after ${TimeoutMs}ms — proceeding without lock."
    return $null
}

function script:ReleaseLock {
    <#
    .SYNOPSIS
        Closes and disposes a lock FileStream and removes the .lock file.
    #>
    param(
        [System.IO.FileStream]$Stream,
        [string]$LockFile
    )
    if ($null -ne $Stream) {
        $Stream.Close()
        $Stream.Dispose()
        Remove-Item -Path $LockFile -ErrorAction SilentlyContinue
    }
}

function script:WithIdxLock {
    <#
    .SYNOPSIS
        Acquires the index advisory lock, runs a scriptblock, then releases the lock.
        Callers performing LoadIdx → modify → SaveIdx can wrap the sequence here for
        full read-modify-write atomicity.
    #>
    param([scriptblock]$Action)
    $lockFile = "$script:IdxFile.lock"
    $lock = script:AcquireLock -LockFile $lockFile
    try {
        & $Action
    } finally {
        script:ReleaseLock -Stream $lock -LockFile $lockFile
    }
}

function script:InitEnv {
    $script:FtsCacheFile = Join-Path $script:Home 'fts-cache.json'

    # Resolve workspace config file path (env override or cwd/.pssnips/config.json)
    $wsDir = if ($env:PSSNIPS_WORKSPACE) { $env:PSSNIPS_WORKSPACE } else { Join-Path (Get-Location) '.pssnips' }
    $script:WorkspaceCfgFile = Join-Path $wsDir 'config.json'

    script:EnsureDirs

    # Clean up any stale .lock files left by a previous crashed session.
    Get-Item "$script:SnipDir\*.lock", "$script:IdxFile.lock", "$script:CfgFile.lock" `
        -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue

    if (-not (Test-Path $script:CfgFile)) {
        $def = @{}; $script:Defaults.GetEnumerator() | ForEach-Object { $def[$_.Key] = $_.Value }
        script:SaveCfg -Cfg $def
    }
    if (-not (Test-Path $script:IdxFile)) { script:SaveIdx -Idx @{ snippets = @{} } }
    script:InvalidateCache
}

function script:InvalidateCache {
    $script:IdxDirty     = $true
    $script:CfgDirty     = $true
    $script:CompleterCache = $null
    $script:FtsCache     = $null
}

