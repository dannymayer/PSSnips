<#
.NOTES
    Module  : PSSnips
    Version : 1.0.1
    Author  : PSSnips Contributors
    License : MIT
    Requires: PowerShell 7.0+, Windows
    Purpose : Terminal-first snippet manager with GitHub Gist integration.
              Store, search, edit (Microsoft Edit / nvim / VS Code), run, and
              sync local code snippets. Supports PS1, Python, JS, Batch, Bash,
              Ruby, and Go execution.
    Usage   : Import-Module .\PSSnips.psd1
              snip         # interactive TUI
              snip help    # command reference
#>
#Requires -Version 7.0

Set-StrictMode -Version Latest
# $ErrorActionPreference is intentionally NOT set at module scope to avoid bleeding
# into the caller's session. Individual functions use -ErrorAction Stop/Continue as needed.

#region ─── Module-Scoped Data ──────────────────────────────────────────────
# Persistent paths, default settings, display colour map, and snippet templates
# that are shared across all functions in the module.

$script:Home      = Join-Path $env:USERPROFILE '.pssnips'
$script:CfgFile   = Join-Path $script:Home 'config.json'
$script:IdxFile   = Join-Path $script:Home 'index.json'
$script:SnipDir   = Join-Path $script:Home 'snippets'

# Advisory lock timeout (ms). Callers degrade gracefully on timeout rather than throw.
$script:LockTimeoutMs = 3000

$script:Defaults = [ordered]@{
    SnippetsDir     = $script:SnipDir
    Editor          = 'edit'
    EditorFallbacks = @('nvim','code','notepad')
    GitHubToken     = ''
    GitHubUsername  = ''
    DefaultLanguage = 'ps1'
    ConfirmDelete   = $true
    MaxHistory        = 10
    GitLabToken       = ''
    GitLabUrl         = 'https://gitlab.com'
    SharedSnippetsDir = ''
}

# Map extension → color for display
$script:LangColor = @{
    ps1  = 'Cyan';    psm1 = 'Cyan';   py  = 'Yellow'; js  = 'Yellow'
    ts   = 'Blue';    bat  = 'Gray';   cmd = 'Gray';   sh  = 'Green'
    rb   = 'Red';     go   = 'Cyan';   cs  = 'Magenta';sql = 'DarkCyan'
    txt  = 'White';   md   = 'White';  json= 'DarkYellow'
}

# Placeholder templates for new snippets
$script:Templates = @{
    ps1  = "# {name}`n# {desc}`n`n"
    py   = "# {name}`n# {desc}`n`n"
    js   = "// {name}`n// {desc}`n`n"
    ts   = "// {name}`n// {desc}`n`n"
    bat  = "@echo off`nREM {name}`nREM {desc}`n`n"
    sh   = "#!/usr/bin/env bash`n# {name}`n# {desc}`n`n"
    rb   = "# {name}`n# {desc}`n`n"
    go   = "package main`n`n// {name} – {desc}`nfunc main() {`n`t`n}`n"
}

# Index/config in-memory caches (dirty = $true means reload from disk is needed)
$script:IdxCache     = $null
$script:IdxDirty     = $true
$script:CfgCache     = $null
$script:CfgDirty     = $true

# Argument-completer TTL cache
$script:CompleterCache     = $null
$script:CompleterCacheTime = [datetime]::MinValue
$script:CompleterTtlSecs   = 10

# Full-text search sidecar cache (path set in InitEnv)
$script:FtsCache     = $null
$script:FtsCacheFile = ''

#endregion

#region ─── Private Helpers ──────────────────────────────────────────────────
# Internal helper functions (script: scope) used by the public API.
# These are not exported and are not part of the public interface.

function script:Out-Banner {
    $lines = @(
        "  ____  ____  ____       _            ",
        " |  _ \/ ___||  _ \ ___ (_)_ __  ___  ",
        " | |_) \___ \| |_) / __|| | '_ \/ __| ",
        " |  __/ ___) |  __/\__ \| | |_) \__ \ ",
        " |_|  |____/|_|   |___/|_| .__/|___/ ",
        "                         |_|          "
    )
    Write-Host ""
    foreach ($l in $lines) { Write-Host $l -ForegroundColor Cyan }
    Write-Host "  PowerShell Snippet Manager  v1.0`n" -ForegroundColor DarkCyan
}

function script:Out-OK   { param([string]$m) Write-Host "  [+] $m" -ForegroundColor Green }
function script:Out-Err  { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Red }
function script:Out-Warn { param([string]$m) Write-Host "  [~] $m" -ForegroundColor Yellow }
function script:Out-Info { param([string]$m) Write-Host "  [i] $m" -ForegroundColor DarkCyan }

function script:EnsureDirs {
    $cfg = script:LoadCfg
    foreach ($d in @($script:Home, $cfg.SnippetsDir, (Join-Path $script:Home 'history'))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function script:LoadCfg {
    if (-not $script:CfgDirty -and $null -ne $script:CfgCache) {
        return $script:CfgCache
    }
    # Build a plain hashtable copy of defaults (OrderedDictionary has no .Clone())
    $cfg = @{}
    $script:Defaults.GetEnumerator() | ForEach-Object { $cfg[$_.Key] = $_.Value }

    if (Test-Path $script:CfgFile) {
        try {
            $raw = Get-Content $script:CfgFile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) {
                        # -AsHashtable returns a [hashtable] rather than PSCustomObject
                        # for easy key enumeration and merging with the defaults.
                        $loaded = $raw | ConvertFrom-Json -AsHashtable
                        foreach ($k in $loaded.Keys) { $cfg[$k] = $loaded[$k] }
                    }
        } catch { Write-Verbose "LoadCfg: using defaults — $($_.Exception.Message)" }
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
        Acquires $script:CfgFile.lock (exclusive FileShare.None) before writing.
        On lock timeout a Write-Warning is emitted and the write proceeds anyway so
        the caller is never left without a config. The temp file is always cleaned up
        even on error via try/finally.
    #>
    param([hashtable]$Cfg)
    $lockFile = "$script:CfgFile.lock"
    $lock = script:AcquireLock -LockFile $lockFile
    try {
        $tmp = "$script:CfgFile.tmp"
        $Cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $script:CfgFile -Force
        $script:CfgCache = $Cfg
        $script:CfgDirty = $false
    } finally {
        script:ReleaseLock -Stream $lock -LockFile $lockFile
        if (Test-Path "$script:CfgFile.tmp") { Remove-Item "$script:CfgFile.tmp" -ErrorAction SilentlyContinue }
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

function script:GetGitHubToken {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    $cfg = script:LoadCfg
    if ($cfg.ContainsKey('GitHubTokenSecure') -and $cfg.GitHubTokenSecure) {
        try {
            $secure = $cfg.GitHubTokenSecure | ConvertTo-SecureString
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        } catch { Write-Verbose "GetGitHubToken: DPAPI decryption failed — $($_.Exception.Message)" }
    }
    return $cfg.GitHubToken
}

function script:GetGitLabToken {
    if ($env:GITLAB_TOKEN) { return $env:GITLAB_TOKEN }
    $cfg = script:LoadCfg
    if ($cfg.ContainsKey('GitLabTokenSecure') -and $cfg.GitLabTokenSecure) {
        try {
            $secure = $cfg.GitLabTokenSecure | ConvertTo-SecureString
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        } catch { Write-Verbose "GetGitLabToken: DPAPI decryption failed — $($_.Exception.Message)" }
    }
    return $cfg.GitLabToken
}

function script:CallGitHub {
    param(
        [string]$Endpoint,
        [string]$Method = 'GET',
        [hashtable]$Body = $null
    )
    $tok = script:GetGitHubToken
    if (-not $tok) {
        throw "GitHub token not set. Run: snip config -GitHubToken <token>  (or set `$env:GITHUB_TOKEN)"
    }
    $headers = @{
        Authorization        = "Bearer $tok"
        Accept               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'         = 'PSSnips/1.0'
    }
    $p = @{ Uri = "https://api.github.com/$Endpoint"; Method = $Method; Headers = $headers }
    if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p -ErrorAction Stop
}

function script:CallGitLab {
    param(
        [string]$Endpoint,
        [string]$Method   = 'GET',
        [hashtable]$Body  = $null
    )
    $cfg   = script:LoadCfg
    $tok   = script:GetGitLabToken
    if (-not $tok) {
        throw "GitLab token not set. Run: snip config -GitLabToken <token>  (or set `$env:GITLAB_TOKEN)"
    }
    $glUrl = if ($cfg.ContainsKey('GitLabUrl') -and $cfg.GitLabUrl) { $cfg.GitLabUrl.TrimEnd('/') } else { 'https://gitlab.com' }
    $headers = @{ 'PRIVATE-TOKEN' = $tok; 'User-Agent' = 'PSSnips/1.0' }
    $p = @{ Uri = "$glUrl/api/v4/$Endpoint"; Method = $Method; Headers = $headers }
    if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p -ErrorAction Stop
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

function script:GetSharedDir {
    $cfg = script:LoadCfg
    $dir = if ($cfg.ContainsKey('SharedSnippetsDir')) { $cfg['SharedSnippetsDir'] } else { '' }
    if (-not $dir) { script:Out-Warn "SharedSnippetsDir is not configured. Run: Set-SnipConfig -SharedSnippetsDir <path>"; return $null }
    if (-not (Test-Path $dir)) { script:Out-Warn "SharedSnippetsDir '$dir' is not accessible."; return $null }
    return $dir
}

function script:GetContentHash {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    return ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
}

#endregion

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


# Functions to read and write the PSSnips config.json settings file.

function Get-SnipConfig {
    <#
    .SYNOPSIS
        Shows the current PSSnips configuration settings.

    .DESCRIPTION
        Reads and displays all settings from the PSSnips config.json file located in
        the ~/.pssnips directory. Settings include the editor command, GitHub token
        and username, snippet storage path, default language, and delete confirmation
        preference. GitHub tokens are masked in the output, showing only the last
        four characters.

    .EXAMPLE
        Get-SnipConfig

        Displays the full configuration table in the terminal.

    .EXAMPLE
        # Check which editor is configured before editing a snippet
        Get-SnipConfig
        Edit-Snip my-deploy-script

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Output is written directly to the host (formatted table).

    .NOTES
        Configuration is stored as JSON at ~/.pssnips/config.json.
        Use Set-SnipConfig to change individual settings.
    #>
    [CmdletBinding()]
    param()
    script:InitEnv
    $cfg = script:LoadCfg
    Write-Host ""
    Write-Host "  PSSnips Configuration" -ForegroundColor Cyan
    Write-Host "  $('─' * 44)" -ForegroundColor DarkGray
    foreach ($k in $cfg.Keys) {
        $v = $cfg[$k]
        if ($k -in 'GitHubToken','GitLabToken' -and $v) { $v = '[plain-text]' }
        if ($k -in 'GitHubTokenSecure','GitLabTokenSecure' -and $v) { $v = '[DPAPI encrypted]' }
        if ($v -is [array]) { $v = $v -join ', ' }
        Write-Host ("  {0,-22}" -f $k) -ForegroundColor DarkCyan -NoNewline
        Write-Host " $v"
    }
    Write-Host ""
}

function Set-SnipConfig {
    <#
    .SYNOPSIS
        Updates one or more PSSnips configuration settings.

    .DESCRIPTION
        Loads the current configuration from ~/.pssnips/config.json, applies any
        provided parameter values, and saves the updated configuration back to disk.
        Only the parameters you supply are changed; unspecified settings retain their
        current values. Multiple settings can be updated in a single call.

    .PARAMETER Editor
        The command name or path of the preferred text editor (e.g., 'edit', 'nvim',
        'code'). Optional. Falls back through EditorFallbacks if the command is not
        found on PATH.

    .PARAMETER GitHubToken
        A GitHub personal access token (PAT) with the 'gist' scope. Optional.
        Required for all Gist operations. Stored in plain text unless -SecureStorage
        is also specified. Token resolution priority at runtime:
          $env:GITHUB_TOKEN  >  GitHubTokenSecure (DPAPI)  >  GitHubToken (plain-text)
        WARNING: tokens written to config.json are not encrypted by default.
        Consider using $env:GITHUB_TOKEN for improved security.

    .PARAMETER GitLabToken
        A GitLab personal access token with 'api' scope. Optional.
        Required for all GitLab Snippet operations. Stored in plain text unless
        -SecureStorage is also specified. Token resolution priority at runtime:
          $env:GITLAB_TOKEN  >  GitLabTokenSecure (DPAPI)  >  GitLabToken (plain-text)
        WARNING: tokens written to config.json are not encrypted by default.
        Consider using $env:GITLAB_TOKEN for improved security.

    .PARAMETER SecureStorage
        When specified, tokens are encrypted with Windows DPAPI before being written
        to config.json (stored under GitHubTokenSecure / GitLabTokenSecure). DPAPI
        encryption is scoped to the current machine and user account — the encrypted
        value cannot be decrypted on a different machine or by a different user.
        If DPAPI is unavailable, falls back to plain-text storage with a warning.

    .PARAMETER GitHubUsername
        Your GitHub username. Optional. Used to list your own Gists when calling
        Get-GistList without specifying -Username.

    .PARAMETER SnippetsDir
        Absolute path to the directory where snippet files are stored. Optional.
        Defaults to ~/.pssnips/snippets. The directory is created if it does not exist.

    .PARAMETER DefaultLanguage
        The file extension (without dot) used when creating a new snippet without an
        explicit -Language parameter (e.g., 'ps1', 'py', 'js'). Optional.

    .PARAMETER ConfirmDelete
        When $true (the default), Remove-Snip prompts for confirmation before
        deleting. Set to $false to suppress the confirmation prompt globally. Optional.

    .EXAMPLE
        Set-SnipConfig -Editor nvim

        Switches the default editor to Neovim.

    .EXAMPLE
        Set-SnipConfig -GitHubToken 'ghp_abc123' -GitHubUsername 'octocat'

        Saves GitHub credentials to enable Gist integration (plain-text, with warning).

    .EXAMPLE
        Set-SnipConfig -GitHubToken 'ghp_abc123' -SecureStorage

        Saves the token encrypted with DPAPI (machine+user scoped).

    .EXAMPLE
        Set-SnipConfig -DefaultLanguage py -ConfirmDelete $false

        Sets Python as the default language and disables delete confirmation prompts.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host on success.

    .NOTES
        Settings are persisted to ~/.pssnips/config.json as UTF-8 JSON.
        Use $env:GITHUB_TOKEN or $env:GITLAB_TOKEN for the most secure token handling,
        as environment variables are never written to disk.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateNotNullOrEmpty()][string]$Editor,
        [ValidateNotNullOrEmpty()][string]$GitHubToken,
        [ValidateNotNullOrEmpty()][string]$GitLabToken,
        [ValidateNotNullOrEmpty()][string]$GitHubUsername,
        [ValidateNotNullOrEmpty()][string]$SnippetsDir,
        [ValidateNotNullOrEmpty()][string]$DefaultLanguage,
        [nullable[bool]]$ConfirmDelete,
        [switch]$SecureStorage
    )
    script:InitEnv
    $cfg = script:LoadCfg
    if ($Editor)          { $cfg['Editor']          = $Editor          }
    if ($PSBoundParameters.ContainsKey('GitHubToken')) {
        Write-Warning "GitHub tokens stored in config.json are not encrypted. Consider using `$env:GITHUB_TOKEN instead."
        if ($SecureStorage) {
            try {
                $cfg['GitHubTokenSecure'] = $GitHubToken | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                $cfg.Remove('GitHubToken')
            } catch {
                Write-Warning "DPAPI encryption failed; falling back to plain-text storage. Error: $($_.Exception.Message)"
                $cfg['GitHubToken'] = $GitHubToken
            }
        } else {
            $cfg['GitHubToken'] = $GitHubToken
        }
    }
    if ($PSBoundParameters.ContainsKey('GitLabToken')) {
        Write-Warning "GitLab tokens stored in config.json are not encrypted. Consider using `$env:GITLAB_TOKEN instead."
        if ($SecureStorage) {
            try {
                $cfg['GitLabTokenSecure'] = $GitLabToken | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                $cfg.Remove('GitLabToken')
            } catch {
                Write-Warning "DPAPI encryption failed; falling back to plain-text storage. Error: $($_.Exception.Message)"
                $cfg['GitLabToken'] = $GitLabToken
            }
        } else {
            $cfg['GitLabToken'] = $GitLabToken
        }
    }
    if ($GitHubUsername)  { $cfg['GitHubUsername']  = $GitHubUsername  }
    if ($SnippetsDir)     { $cfg['SnippetsDir']     = $SnippetsDir     }
    if ($DefaultLanguage) { $cfg['DefaultLanguage'] = $DefaultLanguage }
    if ($null -ne $ConfirmDelete) { $cfg['ConfirmDelete'] = $ConfirmDelete }
    script:SaveCfg -Cfg $cfg
    script:Out-OK "Configuration saved."
}

#endregion

#region ─── Snippet CRUD ─────────────────────────────────────────────────────
# Create, read, update, and delete operations for local snippet files.
# Each function maintains both the snippet file on disk and the index.json metadata.

function Get-Snip {
    <#
    .SYNOPSIS
        Lists local snippets with optional filtering by name, description, tag, language, or content.

    .DESCRIPTION
        Reads the snippet index (index.json) and outputs a formatted table of all
        matching snippets. Filtering is case-insensitive and matches against the
        snippet name, its description, and its tags when -Filter is used. When
        -Content is also specified the body of each snippet file is searched as well.
        Use -Tag for an exact tag match or -Language to restrict by file extension.
        Use -SortBy to control ordering: Name (default, ascending), Modified
        (ascending), RunCount (descending), or LastRun (descending). Pinned snippets
        always float to the top of the list regardless of -SortBy. Returns an array
        of PSCustomObject rows so results can be piped to other commands.

    .PARAMETER Filter
        Optional. A wildcard substring matched against the snippet name, description,
        and tags. Accepts partial strings (e.g., 'azure' matches 'azure-deploy').
        When combined with -Content, the snippet file body is also searched.

    .PARAMETER Tag
        Optional. An exact tag value to filter by. The snippet must have this tag
        in its tags array to be included in the results.

    .PARAMETER Language
        Optional. A file extension (without the dot) to restrict results to a single
        language (e.g., 'py', 'ps1', 'js').

    .PARAMETER Content
        Optional switch. When specified together with -Filter, the body of each
        snippet file is also searched for the filter string (case-insensitive).
        Files that cannot be read are silently skipped.

    .PARAMETER SortBy
        Optional. Controls the sort order of the output. Accepted values:
          Name      – alphabetical ascending (default)
          Modified  – last-modified timestamp ascending
          RunCount  – most-run snippets first (descending)
          LastRun   – most-recently run snippets first (descending)
        Pinned snippets always appear before non-pinned ones.

    .EXAMPLE
        Get-Snip

        Lists all snippets in the index, sorted by name.

    .EXAMPLE
        Get-Snip -Filter azure

        Lists all snippets whose name, description, or tags contain 'azure'.

    .EXAMPLE
        Get-Snip -Filter azure -Content

        Lists all snippets whose name, description, tags, OR file body contains 'azure'.

    .EXAMPLE
        Get-Snip -Tag devops -Language ps1

        Lists PowerShell snippets tagged 'devops'.

    .EXAMPLE
        Get-Snip -SortBy RunCount

        Lists all snippets ordered by run frequency (most-run first).

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has Name, Lang, Gist, Tags, Modified, Desc, Runs, and Pinned
        properties. Returns nothing (displays an info message) when no snippets match.

    .NOTES
        The @($m.tags) wrapping inside the filter logic normalises tags to an array
        even when the JSON deserializer returns a bare string for a single-element
        array (a known PowerShell 5.1 ConvertFrom-Json quirk).
        Run history fields (runCount, lastRun) are written to the index by Invoke-Snip.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Position=0)][string]$Filter   = '',
        [string]$Tag      = '',
        [string]$Language = '',
        [switch]$Content,   # when set, also search inside snippet file bodies
        [ValidateSet('Name','Modified','RunCount','LastRun')]
        [string]$SortBy = 'Name',
        [switch]$Shared
    )
    script:InitEnv
    $idx = if ($Shared) {
        $sharedDir = script:GetSharedDir
        if (-not $sharedDir) { return }
        $sharedIdxFile = Join-Path $sharedDir 'shared-index.json'
        if (-not (Test-Path $sharedIdxFile)) {
            script:Out-Info "No shared-index.json found at $sharedDir."
            return
        }
        try {
            $raw = Get-Content $sharedIdxFile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) {
                $si = $raw | ConvertFrom-Json -AsHashtable
                if (-not $si.ContainsKey('snippets')) { $si['snippets'] = @{} }
                $si
            } else { @{ snippets = @{} } }
        } catch { @{ snippets = @{} } }
    } else {
        script:LoadIdx
    }
    if ($idx.snippets.Count -eq 0) {
        script:Out-Info "No snippets yet. Use 'snip new <name>' to create one."
        return
    }

    # Phase 1: Filter — collect matching snippet names
    $matchedNames = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $idx.snippets.Keys) {
        $m  = $idx.snippets[$name]
        # @($m.tags) normalises to array: PS 5.1 ConvertFrom-Json may return a bare
        # string for a single-element JSON array; wrapping with @() is defensive.
        $mf = -not $Filter   -or $name -like "*$Filter*" -or ($m.description -like "*$Filter*") -or
              ((@($m.tags) -join ',') -like "*$Filter*") -or
              ($Content -and $Filter -and (script:SearchSnipContent -Name $name -SearchString $Filter))
        $mt = -not $Tag      -or (@($m.tags) -contains $Tag)
        $ml = -not $Language -or $m.language -eq $Language
        if ($mf -and $mt -and $ml) { $matchedNames.Add($name) }
    }

    # Phase 2: Sort by $SortBy
    $sortedNames = switch ($SortBy) {
        'Modified' {
            $matchedNames | Sort-Object {
                if ($idx.snippets[$_].ContainsKey('modified')) { $idx.snippets[$_]['modified'] } else { '' }
            }
        }
        'RunCount' {
            $matchedNames | Sort-Object {
                if ($idx.snippets[$_].ContainsKey('runCount')) { [int]$idx.snippets[$_]['runCount'] } else { 0 }
            } -Descending
        }
        'LastRun'  {
            $matchedNames | Sort-Object {
                if ($idx.snippets[$_].ContainsKey('lastRun')) { $idx.snippets[$_]['lastRun'] } else { '' }
            } -Descending
        }
        default    { $matchedNames | Sort-Object }   # 'Name' — alphabetical ascending
    }

    # Phase 3: Pinned entries float to the top of the listing
    $pinnedNames    = @($sortedNames | Where-Object {
        $idx.snippets[$_].ContainsKey('pinned') -and $idx.snippets[$_]['pinned'] -eq $true
    })
    $nonPinnedNames = @($sortedNames | Where-Object {
        -not ($idx.snippets[$_].ContainsKey('pinned') -and $idx.snippets[$_]['pinned'] -eq $true)
    })
    $finalNames = @($pinnedNames) + @($nonPinnedNames)

    # Phase 4: Build output objects
    $rows = @(foreach ($name in $finalNames) {
        $m        = $idx.snippets[$name]
        $pinned   = $m.ContainsKey('pinned') -and $m['pinned'] -eq $true
        $runCount = if ($m.ContainsKey('runCount')) { [int]$m['runCount'] } else { 0 }
        [pscustomobject]@{
            Name     = $name
            Lang     = $m.language
            Gist     = if ($Shared) { '[shared]' } elseif ($m.gistId) {'linked'} else {''}
            Source   = if ($Shared) { '[shared]' } else { 'local' }
            Tags     = @($m.tags) -join ', '
            Modified = if ($m.modified) { [datetime]$m.modified | Get-Date -Format 'yyyy-MM-dd' } else { '' }
            Desc     = if ($m.description) { $m.description } else { '' }
            Runs     = $runCount
            Pinned   = $pinned
        }
    })

    if (-not $rows) { script:Out-Info "No snippets match that filter."; return }

    Write-Host ""
    Write-Host ("  {0,-2} {1,-23} {2,-5} {3,-7} {4,-22} {5,-5} {6}" -f '', 'NAME', 'LANG', 'GIST', 'TAGS', 'RUNS', 'MODIFIED') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 80)" -ForegroundColor DarkGray
    foreach ($r in $rows) {
        $c        = script:LangColor -ext $r.Lang
        $pin      = if ($r.Pinned) { '★' } else { ' ' }
        $runsDisp = if ($r.Runs -gt 0) { "$($r.Runs)" } else { '' }
        Write-Host ("  {0,-2} {1,-23} " -f $pin, $r.Name) -ForegroundColor $c -NoNewline
        Write-Host ("{0,-5} {1,-7} {2,-22} {3,-5} {4}" -f $r.Lang, $r.Gist, $r.Tags, $runsDisp, $r.Modified) -ForegroundColor Gray
    }
    Write-Host ""
    return $rows
}

function Show-Snip {
    <#
    .SYNOPSIS
        Displays the content of a named snippet in the terminal.

    .DESCRIPTION
        Reads the snippet file from disk and writes its content to the terminal.
        By default, a decorative header showing the snippet name, description, and
        Gist URL (if linked) is printed before the content. Use -Raw to suppress
        the header and print only the raw file contents. Use -PassThru to return the
        content as a string for use in scripts or pipelines instead of printing it.

    .PARAMETER Name
        Mandatory. The name of the snippet to display (without file extension).

    .PARAMETER Raw
        Optional switch. When specified, suppresses the decorative header and prints
        only the raw file content.

    .PARAMETER PassThru
        Optional switch. When specified, returns the snippet content as a string
        instead of writing to the host. The decorative header is not printed.

    .EXAMPLE
        Show-Snip my-snippet

        Displays the snippet content with a decorative header.

    .EXAMPLE
        Show-Snip my-snippet -PassThru | Set-Clipboard

        Returns the snippet content as a string and copies it to the clipboard.

    .EXAMPLE
        Show-Snip my-snippet -Raw

        Prints the raw file content without any header decoration.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String
        Only when -PassThru is specified. Returns the full file content as a string.
        Otherwise outputs nothing (writes directly to the host).

    .NOTES
        If the snippet name is not found in the file system, an error message is
        displayed and the function returns without throwing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the local snippet')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Raw,
        [switch]$PassThru
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $content = Get-Content $path -Raw -Encoding UTF8
    if ($PassThru) { return $content }

    if (-not $Raw) {
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($Name)) {
            $m = $idx.snippets[$Name]; $c = script:LangColor -ext $m.language
            Write-Host ""
            Write-Host ("  ╔═ {0}" -f $Name) -ForegroundColor $c -NoNewline
            if ($m.description) { Write-Host (" – {0}" -f $m.description) -ForegroundColor DarkGray -NoNewline }
            Write-Host " ═╗" -ForegroundColor $c
            if ($m.gistUrl) { Write-Host "  │ Gist: $($m.gistUrl)" -ForegroundColor DarkCyan }
            Write-Host ""
        }
    }
    Write-Host $content
    if (-not $Raw) { Write-Host "" }
}

function New-Snip {
    <#
    .SYNOPSIS
        Creates a new snippet file and opens it in the configured editor.

    .DESCRIPTION
        Creates a snippet file in the configured snippets directory, registers it in
        the index (index.json), and opens the file in the editor unless -Content is
        provided. When -Content is supplied the file is written with that content and
        the editor is not launched. When no -Content is given, a language-appropriate
        template is written first. If a snippet with the same name already exists the
        function warns and returns without overwriting.

    .PARAMETER Name
        Mandatory. A short identifier for the snippet (no spaces, no extension).
        Used as both the file base name and the index key.

    .PARAMETER Language
        Optional. The file extension (without dot) that determines the snippet's
        language and runner (e.g., 'ps1', 'py', 'js', 'bat', 'sh', 'rb', 'go').
        Defaults to the configured DefaultLanguage (ps1 out of the box).

    .PARAMETER Description
        Optional. A short human-readable description stored in the index and
        shown in Get-Snip listings.

    .PARAMETER Tags
        Optional. An array of tag strings to categorise the snippet
        (e.g., @('devops', 'azure')).

    .PARAMETER Content
        Optional. If provided, this string is written directly to the snippet file
        and the editor is not launched. Useful for programmatic creation.

    .PARAMETER Editor
        Optional. Overrides the configured editor for this single invocation
        (e.g., 'code' to open in VS Code).

    .EXAMPLE
        New-Snip deploy-script -Language ps1 -Description 'Azure deployment'

        Creates a new PowerShell snippet and opens it in the default editor.

    .EXAMPLE
        New-Snip parser -Language py -Tags @('data', 'util')

        Creates a Python snippet tagged 'data' and 'util'.

    .EXAMPLE
        New-Snip hello -Content 'Write-Host "Hello, World!"'

        Creates a snippet with pre-filled content without opening an editor.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success or warning message to the host.

    .NOTES
        Template files for ps1, py, js, ts, bat, sh, rb, and go are automatically
        populated with the snippet name and description as header comments.
        The editor is determined by script:GetEditor which walks the configured
        Editor then EditorFallbacks list.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the new snippet')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Position=1)][string]$Language = '',
        [string]$Description = '',
        [string[]]$Tags      = @(),
        [string]$Content     = '',
        [string]$Editor      = '',
        [switch]$Force,
        [switch]$IgnoreDuplicate
    )
    script:InitEnv
    $cfg = script:LoadCfg
    $idx = script:LoadIdx
    if ($idx.snippets.ContainsKey($Name)) {
        if (-not $Force -or -not $Content) {
            script:Out-Warn "Snippet '$Name' already exists. Use 'snip edit $Name' to modify it."; return
        }
        # Overwriting with -Force -Content: version existing content first
        $existingPath = script:FindFile -Name $Name
        if ($existingPath -and (Test-Path $existingPath)) {
            script:SaveVersion -Name $Name -FilePath $existingPath
        }
    }
    if (-not $Language) { $Language = $cfg.DefaultLanguage }
    $langExt = $Language.TrimStart('.').ToLower()

    $filePath     = Join-Path $cfg.SnippetsDir "$Name.$langExt"
    $finalContent = if ($Content) {
        $Content
    } else {
        if ($script:Templates.ContainsKey($langExt)) {
            $script:Templates[$langExt] -replace '\{name\}',$Name -replace '\{desc\}',$Description
        } else { "" }
    }

    # Duplicate content detection
    $newHash = script:GetContentHash -Content $finalContent
    if (-not $IgnoreDuplicate) {
        $dupEntry = $idx.snippets.Keys | Where-Object {
            $_ -ne $Name -and $idx.snippets[$_].ContainsKey('contentHash') -and
            $idx.snippets[$_]['contentHash'] -eq $newHash
        } | Select-Object -First 1
        if ($dupEntry) {
            script:Out-Warn "Duplicate: content is identical to existing snippet '$dupEntry'."
            script:Out-Info "Use -IgnoreDuplicate to save anyway."
            return
        }
    }

    Set-Content $filePath -Value $finalContent -Encoding UTF8

    $idx.snippets[$Name] = @{
        name = $Name; description = $Description; language = $langExt
        tags = $Tags; created = (Get-Date -Format 'o'); modified = (Get-Date -Format 'o')
        gistId = $null; gistUrl = $null; contentHash = $newHash
    }
    script:SaveIdx -Idx $idx
    script:UpdateFts -Name $Name
    script:Out-OK "Snippet '$Name' ($langExt) created."

    if (-not $Content) { Edit-Snip -Name $Name -Editor $Editor }
}

function Add-Snip {
    <#
    .SYNOPSIS
        Adds a new snippet from an existing file or pipeline input.

    .DESCRIPTION
        Imports content into PSSnips from two sources:
          File     – reads a file from disk via -Path. The language is inferred from
                     the source file's extension when -Language is not specified.
          Pipeline – collects lines piped into the function and joins them with
                     newlines. Requires -Language when the extension cannot be
                     inferred from context.
        The snippet file is written to the configured SnippetsDir and registered in
        the index. Use -Force to overwrite an existing snippet with the same name.

    .PARAMETER Name
        Mandatory. The identifier for the new snippet (no spaces, no extension).

    .PARAMETER Path
        Optional (File parameter set). Path to the source file to import.
        The language is derived from the file extension when -Language is omitted.

    .PARAMETER InputObject
        Optional (Pipe parameter set). Accepts string lines from the pipeline.
        All lines are collected and joined before saving.

    .PARAMETER Language
        Optional. Overrides the inferred or default language/extension.

    .PARAMETER Description
        Optional. Short description stored in the index.

    .PARAMETER Tags
        Optional. Array of tag strings for the snippet.

    .PARAMETER Force
        Optional switch. Overwrites an existing snippet with the same name without
        prompting.

    .EXAMPLE
        Add-Snip my-script -Path .\deploy.ps1

        Imports deploy.ps1 as a snippet named 'my-script'.

    .EXAMPLE
        Get-Content .\parser.py | Add-Snip parser -Language py

        Pipes a Python file's contents into a new snippet named 'parser'.

    .INPUTS
        System.String[]
        Accepts string lines via the pipeline when using the Pipe parameter set.

    .OUTPUTS
        None. Writes a confirmation message to the host.

    .NOTES
        The Pipe parameter set collects all input in the process block and writes
        the snippet only in the end block after the pipeline has been fully read.
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name for the imported snippet')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(ParameterSetName='File', Position=1)][string]$Path,
        [Parameter(ParameterSetName='Pipe', ValueFromPipeline)][string[]]$InputObject,
        [string]$Language    = '',
        [string]$Description = '',
        [string[]]$Tags      = @(),
        [switch]$Force,
        [switch]$IgnoreDuplicate
    )
    begin   { $pipeContent = [System.Collections.Generic.List[string]]::new() }
    process { if ($PSCmdlet.ParameterSetName -eq 'Pipe' -and $InputObject) { $pipeContent.AddRange($InputObject) } }
    end {
        script:InitEnv
        $cfg = script:LoadCfg
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($Name) -and -not $Force) {
            script:Out-Warn "Snippet '$Name' already exists. Use -Force to overwrite."; return
        }
        $langHint = $Language
        $content = switch ($PSCmdlet.ParameterSetName) {
            'File' {
                if (-not $Path) { Write-Error "Specify -Path." -ErrorAction Continue; return }
                if (-not (Test-Path $Path)) { Write-Error "File not found: $Path" -ErrorAction Continue; return }
                if (-not $langHint) { $langHint = [System.IO.Path]::GetExtension($Path).TrimStart('.') }
                Get-Content $Path -Raw -Encoding UTF8
            }
            'Clipboard' { Get-Clipboard }
            'Pipe'      { $pipeContent -join "`n" }
        }
        if (-not $langHint) { $langHint = $cfg.DefaultLanguage }
        $langExt = $langHint.TrimStart('.').ToLower()
        $fp = Join-Path $cfg.SnippetsDir "$Name.$langExt"
        if ($idx.snippets.ContainsKey($Name) -and $Force) {
            script:SaveVersion -Name $Name -FilePath $fp
        }

        # Duplicate content detection
        $addHash = script:GetContentHash -Content $content
        if (-not $IgnoreDuplicate) {
            $addDup = $idx.snippets.Keys | Where-Object {
                $_ -ne $Name -and $idx.snippets[$_].ContainsKey('contentHash') -and
                $idx.snippets[$_]['contentHash'] -eq $addHash
            } | Select-Object -First 1
            if ($addDup) {
                script:Out-Warn "Duplicate: content is identical to existing snippet '$addDup'."
                script:Out-Info "Use -IgnoreDuplicate to save anyway."
                return
            }
        }

        Set-Content $fp -Value $content -Encoding UTF8
        $idx.snippets[$Name] = @{
            name = $Name; description = $Description; language = $langExt
            tags = $Tags; created = (Get-Date -Format 'o'); modified = (Get-Date -Format 'o')
            gistId = $null; gistUrl = $null; contentHash = $addHash
        }
        script:SaveIdx -Idx $idx
        script:UpdateFts -Name $Name
        script:Out-OK "Snippet '$Name' ($langExt, $($content.Length) chars) added."
    }
}

function Remove-Snip {
    <#
    .SYNOPSIS
        Deletes a local snippet file and removes its index entry.

    .DESCRIPTION
        Looks up the snippet by name in the index, optionally prompts for
        confirmation (based on the ConfirmDelete config setting or the -Force
        switch), deletes the snippet file from disk, and removes the metadata
        entry from index.json. If the snippet name is not found the function
        displays an error and returns without throwing.

    .PARAMETER Name
        Mandatory. The name of the snippet to delete.

    .PARAMETER Force
        Optional switch. Bypasses the interactive confirmation prompt regardless
        of the ConfirmDelete configuration setting.

    .EXAMPLE
        Remove-Snip old-script

        Deletes 'old-script', prompting for confirmation if ConfirmDelete is $true.

    .EXAMPLE
        Remove-Snip old-script -Force

        Deletes 'old-script' immediately without any confirmation prompt.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success or error message to the host.

    .NOTES
        The physical file and the index entry are both removed. This action is
        not reversible. Linked GitHub Gists are not affected.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to delete')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    if (-not $Force -and $cfg.ConfirmDelete) {
        $yn = Read-Host "  Delete '$Name'? [y/N]"
        if ($yn -notin 'y','Y') { script:Out-Info "Cancelled."; return }
    }
    if ($Force -or $PSCmdlet.ShouldProcess($Name, 'Delete snippet')) {
        $p = script:FindFile -Name $Name
        if ($p -and (Test-Path $p)) { Remove-Item $p -Force }
        $idx.snippets.Remove($Name)
        script:SaveIdx -Idx $idx
        script:RemoveFts -Name $Name
        script:Out-OK "Snippet '$Name' deleted."
    }
}

function Edit-Snip {
    <#
    .SYNOPSIS
        Opens a snippet file in the configured editor and updates its modified timestamp.

    .DESCRIPTION
        Resolves the snippet file path, launches the configured editor (or an override),
        and waits for the editor process to exit. After the editor closes, the snippet's
        'modified' timestamp in index.json is updated to the current UTC time.
        The editor resolution order is: -Editor override → configured Editor →
        EditorFallbacks list (nvim, code, notepad) → notepad as the final fallback.

    .PARAMETER Name
        Mandatory. The name of the snippet to edit.

    .PARAMETER Editor
        Optional. Overrides the configured editor for this invocation only.
        Must be a command resolvable on PATH (e.g., 'code', 'nvim', 'notepad').

    .EXAMPLE
        Edit-Snip my-snippet

        Opens 'my-snippet' in the default configured editor.

    .EXAMPLE
        Edit-Snip my-snippet -Editor code

        Opens 'my-snippet' in Visual Studio Code regardless of the configured editor.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. The editor runs synchronously; control returns after the editor exits.

    .NOTES
        The function calls script:GetEditor which walks the Editor and EditorFallbacks
        configuration keys. The @($cfg.Editor) wrapping ensures the Editor value is
        always iterated as an array even when stored as a bare string in the config.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to edit')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Editor = ''
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    script:SaveVersion -Name $Name -FilePath $path
    $ed = script:GetEditor -Override $Editor
    script:Out-Info "Opening '$Name' in $ed ..."
    & $ed $path

    # Touch the modified timestamp and recompute content hash
    $idx = script:LoadIdx
    if ($idx.snippets.ContainsKey($Name)) {
        $idx.snippets[$Name]['modified'] = Get-Date -Format 'o'
        if (Test-Path $path) {
            $editedContent = Get-Content $path -Raw -Encoding UTF8
            $idx.snippets[$Name]['contentHash'] = script:GetContentHash -Content $editedContent
        }
        script:SaveIdx -Idx $idx
        script:UpdateFts -Name $Name
    }
}

function Invoke-Snip {
    <#
    .SYNOPSIS
        Executes a snippet or runs multiple snippets in sequence (pipeline/chain mode).

    .DESCRIPTION
        Single mode (-Name): resolves the snippet file, substitutes any {{PLACEHOLDER}}
        template variables in the content, then invokes the appropriate language runner.
        Runner selection: .ps1/.psm1 (dot-source), .py (python/python3), .js (node),
        .bat/.cmd (cmd /c), .sh (bash/wsl), .rb (ruby), .go (go run), other (Start-Process).

        Chain mode (-Pipeline): runs multiple snippets sequentially. Prints a header,
        executes each snippet by name in order, and prints a summary. By default stops
        on the first error unless -ContinueOnError is specified.

        After each single execution the snippet's runCount is incremented and lastRun
        is set in index.json. A failure to update run history never prevents output.

    .PARAMETER Name
        Mandatory (Single set). The name of the snippet to execute.

    .PARAMETER Pipeline
        Mandatory (Chain set). An array of snippet names to run in sequence.
        You may also pass a single comma-separated string which is split automatically.

    .PARAMETER ArgumentList
        Optional (Single set). Additional arguments forwarded to the language runner.

    .PARAMETER ContinueOnError
        Optional (Chain set). When set, pipeline execution continues even if a snippet
        in the chain fails. Without this switch, the pipeline stops at the first error.

    .PARAMETER Variables
        Optional (Single set). A hashtable of placeholder values used to fill
        {{VARIABLE_NAME}} placeholders in the snippet body without prompting.
        Keys must match placeholder names exactly (case-insensitive match supported).
        Any placeholder NOT found in this hashtable will be prompted interactively.

    .EXAMPLE
        Invoke-Snip deploy-script

        Runs the 'deploy-script' snippet.

    .EXAMPLE
        Invoke-Snip my-py-script -ArgumentList '--verbose', '--dry-run'

        Runs a Python snippet and passes '--verbose --dry-run' to the interpreter.

    .EXAMPLE
        Invoke-Snip deploy -Variables @{ ENV = 'prod'; REGION = 'eastus' }

        Runs 'deploy' filling {{ENV}} and {{REGION}} without interactive prompts.

    .EXAMPLE
        Invoke-Snip -Pipeline 'setup','build','deploy'

        Runs three snippets in sequence. Stops on the first failure.

    .EXAMPLE
        Invoke-Snip -Pipeline 'setup','build','deploy' -ContinueOnError

        Runs all three snippets, reporting errors but not stopping.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Variable. Output depends on the language runner. PowerShell snippets can
        return objects to the pipeline; other runtimes write to stdout/stderr.

    .NOTES
        Template variables use the syntax {{VARIABLE_NAME}} (uppercase letters,
        digits, and underscores). Matching is case-insensitive for the -Variables
        hashtable lookup. If any substitutions are made, the snippet runs from a
        temporary file that is deleted in a finally block.
        For .sh snippets on Windows, bash is sought first; then wsl bash.
        Run history (runCount, lastRun) is updated in index.json after execution.
    #>
    [CmdletBinding(DefaultParameterSetName='Single')]
    param(
        [Parameter(Mandatory, Position=0, ParameterSetName='Single', HelpMessage='Name of the snippet to run')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName='Chain', HelpMessage='Array of snippet names to run in sequence')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Pipeline,

        [Parameter(Position=1, ValueFromRemainingArguments, ParameterSetName='Single')]
        [string[]]$ArgumentList = @(),

        [Parameter(ParameterSetName='Chain')]
        [switch]$ContinueOnError,

        [Parameter(ParameterSetName='Single')]
        [hashtable]$Variables = @{}
    )

    # ── Chain / Pipeline mode ────────────────────────────────────────────────
    if ($PSCmdlet.ParameterSetName -eq 'Chain') {
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $Pipeline) {
            foreach ($part in ($entry -split ',')) {
                $trimmed = $part.Trim()
                if ($trimmed) { $names.Add($trimmed) }
            }
        }
        $arrow  = ' → '
        script:Out-Info ("Running pipeline: {0}" -f ($names -join $arrow))
        Write-Host ""

        $succeeded = 0
        $stopped   = $null
        for ($i = 0; $i -lt $names.Count; $i++) {
            $sn = $names[$i]
            $snipPath = script:FindFile -Name $sn
            if (-not $snipPath -or -not (Test-Path $snipPath)) {
                script:Out-Err "Pipeline snippet '$sn' not found."
                if (-not $ContinueOnError) {
                    $stopped = $sn
                    break
                }
                continue
            }
            try {
                Invoke-Snip -Name $sn
                $succeeded++
            } catch {
                script:Out-Err "Pipeline snippet '$sn' failed: $_"
                if (-not $ContinueOnError) {
                    $stopped = $sn
                    break
                }
            }
        }

        Write-Host ""
        if ($stopped) {
            script:Out-Warn ("Pipeline stopped at '{0}' ({1}/{2} ran)" -f $stopped, $i, $names.Count)
        } else {
            script:Out-OK ("Pipeline complete: {0}/{1} succeeded" -f $succeeded, $names.Count)
        }
        return
    }

    # ── Single mode ──────────────────────────────────────────────────────────
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $ext     = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
    $content = Get-Content $path -Raw -Encoding UTF8

    # Template variable substitution
    $placeholders = @([regex]::Matches($content, '\{\{([A-Z0-9_]+)\}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
        ForEach-Object { $_.Groups[1].Value.ToUpper() } | Select-Object -Unique)

    $resolvedVars = @{}
    foreach ($k in $Variables.Keys) { $resolvedVars[$k.ToUpper()] = $Variables[$k] }

    foreach ($ph in $placeholders) {
        if (-not $resolvedVars.ContainsKey($ph)) {
            $resolvedVars[$ph] = Read-Host "  Value for {{$ph}}"
        }
    }

    $runPath = $path
    $tmpFile = $null
    if ($placeholders.Count -gt 0) {
        $substituted = $content
        foreach ($ph in $placeholders) {
            $substituted = $substituted -replace [regex]::Escape("{{$ph}}"), $resolvedVars[$ph]
        }
        $tmpFile = Join-Path $env:TEMP "pssnips_var_$([System.IO.Path]::GetRandomFileName()).$ext"
        Set-Content $tmpFile -Value $substituted -Encoding UTF8
        $runPath = $tmpFile
    }

    script:Out-Info "Running '$Name' [$ext] ..."
    Write-Host ""

    try {
        switch ($ext) {
            { $_ -in 'ps1','psm1' } { & $runPath @ArgumentList }
            'py' {
                $py = @('python','python3') | Where-Object { Get-Command $_ -EA 0 } | Select-Object -First 1
                if ($py) { & $py $runPath @ArgumentList } else { Write-Error "Python not found in PATH." -ErrorAction Continue }
            }
            'js' {
                if (Get-Command node -EA 0) { & node $runPath @ArgumentList } else { Write-Error "Node.js not found in PATH." -ErrorAction Continue }
            }
            { $_ -in 'bat','cmd' } { & cmd /c $runPath @ArgumentList }
            'sh' {
                if     (Get-Command bash -EA 0) { & bash $runPath @ArgumentList }
                elseif (Get-Command wsl  -EA 0) { & wsl  bash $runPath @ArgumentList }
                else { Write-Error "Bash not found. Install WSL or Git Bash." -ErrorAction Continue }
            }
            'rb' {
                if (Get-Command ruby -EA 0) { & ruby $runPath @ArgumentList } else { Write-Error "Ruby not found in PATH." -ErrorAction Continue }
            }
            'go' {
                if (Get-Command go -EA 0) { & go run $runPath @ArgumentList } else { Write-Error "Go not found in PATH." -ErrorAction Continue }
            }
            default {
                script:Out-Warn "No built-in runner for '.$ext'. Opening with default app ..."
                Start-Process $runPath
            }
        }
    } finally {
        if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
    }

    # Update run history — wrapped in try/catch so a save failure never hides output
    try {
        $idxH = script:LoadIdx
        if ($idxH.snippets.ContainsKey($Name)) {
            $rc = if ($idxH.snippets[$Name].ContainsKey('runCount')) { [int]$idxH.snippets[$Name]['runCount'] } else { 0 }
            $idxH.snippets[$Name]['runCount'] = $rc + 1
            $idxH.snippets[$Name]['lastRun']  = Get-Date -Format 'o'
            script:SaveIdx -Idx $idxH
        }
    } catch { Write-Verbose "Run-history update failed (non-fatal): $_" }
}

function Get-SnipHistory {
    <#
    .SYNOPSIS
        Lists saved version history for a snippet.

    .DESCRIPTION
        Returns all timestamped version snapshots for the named snippet stored in
        the ~/.pssnips/history/<name> directory. Versions are listed newest first,
        numbered from 1 (most recent). Version snapshots are created automatically
        by Edit-Snip (before the editor opens), Add-Snip -Force, and New-Snip -Force
        -Content. Use Restore-Snip to roll back to any previous version.

    .PARAMETER Name
        Mandatory. The name of the snippet whose history to display.

    .EXAMPLE
        Get-SnipHistory my-snippet

        Lists all saved versions of 'my-snippet', newest first.

    .EXAMPLE
        $history = Get-SnipHistory my-snippet
        $history[0].Path  # path to the most recent version file

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has Version (int), Timestamp (datetime), Size (int), and
        Path (string) properties. Returns nothing when no history exists.

    .NOTES
        History snapshots are pruned automatically to MaxHistory (default 10)
        entries per snippet. Older snapshots are removed first when the limit is
        exceeded. The history directory is at ~/.pssnips/history/<snippetName>/.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to show history for')]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    script:InitEnv
    $histDir = Join-Path (Join-Path $script:Home 'history') $Name
    if (-not (Test-Path $histDir)) {
        script:Out-Info "No history for '$Name'."
        return @()
    }
    $files = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) {
        script:Out-Info "No history for '$Name'."
        return @()
    }

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f  = $files[$i]
        $ts = try { [datetime]::ParseExact($f.BaseName, 'yyyyMMddHHmmss', $null) } catch { $f.LastWriteTime }
        $rows.Add([pscustomobject]@{
            Version   = $i + 1
            Timestamp = $ts
            Size      = $f.Length
            Path      = $f.FullName
        })
    }

    Write-Host ""
    Write-Host ("  Version history for '{0}'" -f $Name) -ForegroundColor Cyan
    Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
    Write-Host ("  {0,-8} {1,-22} {2,-8} {3}" -f 'VERSION','TIMESTAMP','SIZE','PATH') -ForegroundColor DarkCyan
    foreach ($r in $rows) {
        Write-Host ("  {0,-8} {1,-22} {2,-8} {3}" -f $r.Version, ($r.Timestamp | Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $r.Size, $r.Path) -ForegroundColor Gray
    }
    Write-Host ""
    return $rows.ToArray()
}

function Restore-Snip {
    <#
    .SYNOPSIS
        Restores a snippet to a previous version from its version history.

    .DESCRIPTION
        Looks up the version history for the named snippet, saves the current content
        as a new history entry (to allow re-restore if needed), then copies the
        selected historical version back to the snippets directory and updates the
        snippet's 'modified' timestamp in the index. Version 1 is the most recent
        saved version, version 2 is the second most recent, and so on. Use
        Get-SnipHistory to see the available version numbers.

    .PARAMETER Name
        Mandatory. The name of the snippet to restore.

    .PARAMETER Version
        Optional. The version number to restore. 1 is the most recent saved version
        (default). Use Get-SnipHistory to see available version numbers.

    .EXAMPLE
        Restore-Snip my-snippet

        Restores 'my-snippet' to its most recent saved version (Version 1).

    .EXAMPLE
        Restore-Snip my-snippet -Version 3

        Restores 'my-snippet' to the third most recent saved version.

    .EXAMPLE
        Get-SnipHistory my-snippet
        Restore-Snip my-snippet -Version 2

        Lists versions, then restores the second most recent one.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success or error message to the host.

    .NOTES
        The current snippet content is saved as a new history entry before
        overwriting, so you can re-restore the version you are replacing.
        Supports -WhatIf via SupportsShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to restore')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Position=1)]
        [int]$Version = 1
    )
    script:InitEnv
    $histDir = Join-Path (Join-Path $script:Home 'history') $Name
    if (-not (Test-Path $histDir)) {
        Write-Error "No history found for '$Name'." -ErrorAction Continue; return
    }
    $files = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) {
        Write-Error "No history entries found for '$Name'." -ErrorAction Continue; return
    }
    if ($Version -lt 1 -or $Version -gt $files.Count) {
        Write-Error "Version $Version is out of range. Available: 1–$($files.Count)." -ErrorAction Continue; return
    }
    $histFile = $files[$Version - 1]
    $path = script:FindFile -Name $Name
    if (-not $path) {
        Write-Error "Snippet file for '$Name' not found." -ErrorAction Continue; return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Restore version $Version")) {
        # Read restore content BEFORE saving current version (avoids same-second timestamp collision)
        $restoreContent = Get-Content $histFile.FullName -Raw -Encoding UTF8
        # Save current as new history entry before overwriting
        script:SaveVersion -Name $Name -FilePath $path
        Set-Content -Path $path -Value $restoreContent -Encoding UTF8
        # Update modified timestamp
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($Name)) {
            $idx.snippets[$Name]['modified'] = Get-Date -Format 'o'
            script:SaveIdx -Idx $idx
        }
        script:Out-OK "Snippet '$Name' restored to version $Version ($(($histFile.LastWriteTime | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))."
    }
}

function Test-Snip {
    <#
    .SYNOPSIS
        Runs PSScriptAnalyzer lint checks on a PowerShell snippet.

    .DESCRIPTION
        Resolves the snippet file path, verifies PSScriptAnalyzer is available, and
        runs Invoke-ScriptAnalyzer against the file. Results are displayed in a
        colour-coded table: errors in Red, warnings in Yellow, information in DarkCyan.
        When no issues are found a green success message is printed. Only applies to
        .ps1 and .psm1 files; an informational message is shown for other extensions.

    .PARAMETER Name
        Mandatory. The name of the snippet to analyse.

    .PARAMETER Severity
        Optional. Restrict results to a specific severity level: Error, Warning,
        Information, or ParseError. When omitted all severities are returned.

    .PARAMETER PassThru
        Optional switch. Returns the raw Invoke-ScriptAnalyzer result objects
        instead of printing the formatted table. Useful for scripted inspection.

    .EXAMPLE
        Test-Snip my-snippet

        Runs all PSScriptAnalyzer rules against 'my-snippet.ps1'.

    .EXAMPLE
        Test-Snip my-snippet -Severity Error

        Reports only Error-severity findings for 'my-snippet'.

    .EXAMPLE
        $results = Test-Snip my-snippet -PassThru
        $results | Where-Object Severity -eq 'Error'

        Returns raw result objects for further processing.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Only when -PassThru is specified. Otherwise writes to the host.

    .NOTES
        Requires the PSScriptAnalyzer module. Install with:
          Install-Module PSScriptAnalyzer -Scope CurrentUser
        Test-Snip only analyses .ps1 and .psm1 files. Other extensions receive
        an informational message and the function returns without error.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to analyse')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [ValidateSet('Error','Warning','Information','ParseError')]
        [string]$Severity = '',
        [switch]$PassThru
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $ext = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
    if ($ext -notin 'ps1','psm1') {
        script:Out-Info "Analysis only applies to PowerShell files (.ps1, .psm1). '$Name' is a .$ext file."
        return
    }

    $psa = @(Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction SilentlyContinue)
    if ($psa.Count -eq 0) {
        script:Out-Warn "PSScriptAnalyzer is not installed."
        script:Out-Info "Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser"
        return
    }

    Import-Module PSScriptAnalyzer -ErrorAction Stop

    $params = @{ Path = $path }
    if ($Severity) { $params['Severity'] = $Severity }
    $results = @(Invoke-ScriptAnalyzer @params -ErrorAction SilentlyContinue)

    if ($PassThru) { return $results }

    if ($results.Count -eq 0) {
        Write-Host ("  ✓ No issues found in '{0}'." -f $Name) -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host ("  PSScriptAnalyzer results for '{0}'" -f $Name) -ForegroundColor Cyan
    Write-Host "  $('─' * 70)" -ForegroundColor DarkGray
    Write-Host ("  {0,-40} {1,-12} {2,-5} {3}" -f 'RULE','SEVERITY','LINE','MESSAGE') -ForegroundColor DarkCyan
    foreach ($r in $results) {
        $color = switch ($r.Severity.ToString()) {
            'Error'       { 'Red' }
            'Warning'     { 'Yellow' }
            'Information' { 'DarkCyan' }
            default       { 'Gray' }
        }
        $rule = if ($r.RuleName.Length -gt 38) { $r.RuleName.Substring(0,35) + '...' } else { $r.RuleName }
        $msg  = if ($r.Message.Length -gt 40)  { $r.Message.Substring(0,37)  + '...' } else { $r.Message  }
        Write-Host ("  {0,-40} {1,-12} {2,-5} {3}" -f $rule, $r.Severity, $r.Line, $msg) -ForegroundColor $color
    }
    Write-Host ""
}

function Copy-Snip {
    <#
    .SYNOPSIS
        Copies a snippet's full content to the Windows clipboard.

    .DESCRIPTION
        Retrieves the content of the named snippet via Show-Snip -PassThru and
        passes it to Set-Clipboard. The function writes a confirmation message if
        successful and does nothing if the snippet is not found (Show-Snip handles
        the error message in that case).

    .PARAMETER Name
        Mandatory. The name of the snippet whose content should be copied.

    .EXAMPLE
        Copy-Snip my-snippet

        Copies the content of 'my-snippet' to the clipboard.

    .EXAMPLE
        # Quickly grab a snippet to paste into a terminal
        Copy-Snip azure-login
        # then Ctrl+V in any application

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host on success.

    .NOTES
        Requires a Windows clipboard (Set-Clipboard). In headless or SSH sessions
        where the clipboard is unavailable, Set-Clipboard may throw; the error is
        not suppressed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to copy')]
        [ValidateNotNullOrEmpty()]
        [string]$Name)
    $content = Show-Snip -Name $Name -PassThru
    if ($content) { Set-Clipboard -Value $content; script:Out-OK "'$Name' copied to clipboard." }
}

function Set-SnipTag {
    <#
    .SYNOPSIS
        Manages the tags on a local snippet: replace, add, or remove individual tags.
        Also supports pinning (favouriting) snippets.

    .DESCRIPTION
        Loads the snippet's current tags from index.json and applies one of three
        mutations depending on the parameters provided:
          -Tags    Replaces all existing tags with the supplied array.
          -Add     Appends each supplied tag that is not already present (no duplicates).
          -Remove  Removes each supplied tag from the current tag list.
        The updated tag list is saved back to index.json and the snippet's 'modified'
        timestamp is refreshed. Tags are stored as a string array in the index.

        Pin/Unpin operations are independent of tag operations and can be combined:
          -Pin     Marks the snippet as a favourite (pinned = $true).
          -Unpin   Removes the favourite mark (pinned = $false).

    .PARAMETER Name
        Mandatory. The name of the snippet to update.

    .PARAMETER Tags
        Optional. Replaces the snippet's entire tag set with these values.

    .PARAMETER Add
        Optional. Tags to append to the existing set. Duplicates are silently ignored.

    .PARAMETER Remove
        Optional. Tags to remove from the existing set. Tags not present are ignored.

    .PARAMETER Pin
        Optional switch. Marks the snippet as pinned (favourite). Pinned snippets
        appear at the top of all Get-Snip listings with a ★ indicator.

    .PARAMETER Unpin
        Optional switch. Removes the pinned (favourite) mark from the snippet.

    .EXAMPLE
        Set-SnipTag my-snippet -Tags @('devops', 'azure')

        Replaces all tags on 'my-snippet' with 'devops' and 'azure'.

    .EXAMPLE
        Set-SnipTag my-snippet -Add 'cloud'

        Appends the tag 'cloud' to the existing tags without removing any.

    .EXAMPLE
        Set-SnipTag my-snippet -Remove 'old-tag'

        Removes the tag 'old-tag' while keeping all other tags intact.

    .EXAMPLE
        Set-SnipTag my-snippet -Pin

        Marks 'my-snippet' as a favourite so it sorts to the top of all listings.

    .EXAMPLE
        Set-SnipTag my-snippet -Pin -Add 'cloud'

        Pins the snippet AND appends the tag 'cloud' in a single call.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message listing the updated tags.

    .NOTES
        Tags are normalised through [System.Collections.Generic.List[string]] to
        guarantee correct array serialisation in JSON (PowerShell 7.0+ ConvertTo-Json
        preserves single-element arrays natively, but the List normalisation is
        retained for defensive correctness).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to tag')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string[]]$Tags   = @(),
        [string[]]$Add    = @(),
        [string[]]$Remove = @(),
        [switch]$Pin,
        [switch]$Unpin
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }
    $current = [System.Collections.Generic.List[string]]@()
    if ($idx.snippets[$Name].tags) {
        # [string[]]@() cast ensures AddRange receives a typed array even when
        # JSON deserialization returns a PSCustomObject or bare string for tags.
        $current.AddRange([string[]]@($idx.snippets[$Name].tags))
    }
    if ($Tags)   { $current.Clear(); $current.AddRange($Tags) }
    foreach ($t in $Add)    { if ($t -notin $current) { $current.Add($t) } }
    foreach ($t in $Remove) { $current.Remove($t) | Out-Null }
    $idx.snippets[$Name]['tags']     = $current.ToArray()
    $idx.snippets[$Name]['modified'] = Get-Date -Format 'o'

    # Pin / Unpin — independent of tag operations
    if ($Pin)   { $idx.snippets[$Name]['pinned'] = $true  }
    if ($Unpin) { $idx.snippets[$Name]['pinned'] = $false }

    script:SaveIdx -Idx $idx
    script:Out-OK "Tags updated: $($current -join ', ')"
}

#endregion

#region ─── Backup and Restore ───────────────────────────────────────────────
# Export-SnipCollection and Import-SnipCollection provide portable ZIP backups
# of the local snippet collection, enabling migration between machines and
# safe archiving before major changes.

function Export-SnipCollection {
    <#
    .SYNOPSIS
        Exports the full local snippet collection to a portable ZIP archive.

    .DESCRIPTION
        Gathers all snippet files from the configured SnippetsDir, the index.json
        metadata file, and (optionally) config.json, then packages them into a ZIP
        archive using Compress-Archive. The archive layout mirrors the PSSnips data
        directory so that Import-SnipCollection can restore it correctly:
            snippets\  — all snippet files
            index.json — snippet metadata index
            config.json (optional)
        The default destination is ~/Desktop/PSSnips-backup-<yyyyMMdd-HHmmss>.zip.

    .PARAMETER Path
        Optional. Destination path for the ZIP file. When omitted, the archive is
        written to the current user's Desktop with a timestamped name.

    .PARAMETER IncludeConfig
        Optional switch. Also includes config.json in the backup. A warning is
        displayed because config.json may contain a GitHub personal access token.

    .EXAMPLE
        Export-SnipCollection

        Creates a timestamped backup ZIP on the Desktop.

    .EXAMPLE
        Export-SnipCollection -Path C:\Backups\my-snips.zip

        Creates the backup at the specified path.

    .EXAMPLE
        Export-SnipCollection -IncludeConfig

        Includes config.json in the archive (warns about potential token exposure).

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success message with the ZIP path and file count to the host.

    .NOTES
        Requires PowerShell 5.0+ for Compress-Archive (already satisfied by the
        module's #Requires -Version 7.0 declaration).
        The archive is created via a temporary staging directory that is removed
        automatically on completion or error.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = '',
        [switch]$IncludeConfig
    )
    script:InitEnv
    $cfg = script:LoadCfg

    # Resolve destination path
    if (-not $Path) {
        $ts   = Get-Date -Format 'yyyyMMdd-HHmmss'
        $Path = Join-Path ([System.Environment]::GetFolderPath('Desktop')) "PSSnips-backup-$ts.zip"
    }

    if ($IncludeConfig) {
        script:Out-Warn "config.json may contain a GitHub personal access token in plain text."
    }

    # Collect source files
    $snipFiles = @(Get-ChildItem $cfg.SnippetsDir -File -ErrorAction SilentlyContinue)
    $fileCount = $snipFiles.Count + $(if (Test-Path $script:IdxFile) { 1 } else { 0 }) +
                 $(if ($IncludeConfig -and (Test-Path $script:CfgFile)) { 1 } else { 0 })

    if ($fileCount -eq 0) { script:Out-Warn "No files found to backup."; return }

    $stageDir = Join-Path $env:TEMP "pssnips_export_$([System.IO.Path]::GetRandomFileName())"
    try {
        $stageSnips = Join-Path $stageDir 'snippets'
        New-Item -ItemType Directory -Path $stageSnips -Force | Out-Null

        foreach ($f in $snipFiles) {
            Copy-Item $f.FullName (Join-Path $stageSnips $f.Name) -Force
        }
        if (Test-Path $script:IdxFile) {
            Copy-Item $script:IdxFile (Join-Path $stageDir 'index.json') -Force
        }
        if ($IncludeConfig -and (Test-Path $script:CfgFile)) {
            Copy-Item $script:CfgFile (Join-Path $stageDir 'config.json') -Force
        }

        Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $Path -Force -ErrorAction Stop
        script:Out-OK "Backup created: $Path ($fileCount file(s))"
    } catch {
        Write-Error "Failed to create backup: $_" -ErrorAction Continue
    } finally {
        if (Test-Path $stageDir) { Remove-Item $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Import-SnipCollection {
    <#
    .SYNOPSIS
        Restores a snippet collection from a PSSnips backup ZIP archive.

    .DESCRIPTION
        Extracts a ZIP archive created by Export-SnipCollection and copies the
        snippet files and index into the configured SnippetsDir. Three modes:

          Default (no switches)
            If the snippets directory already contains files, warns and aborts to
            prevent accidental overwrites. Use -Merge or -Force to proceed.

          -Merge
            Adds backup snippets that do not already exist locally. Existing
            snippets are preserved unless -Force is also specified.

          -Force (without -Merge)
            Replaces all local snippets with the backup contents.

          -Merge -Force
            Imports all backup snippets, overwriting any local conflicts.

    .PARAMETER Path
        Mandatory. Path to the PSSnips backup ZIP file created by Export-SnipCollection.

    .PARAMETER Merge
        Optional switch. Merges backup snippets into the existing collection.
        New snippets from the backup are added; existing local snippets are kept
        unless -Force is also provided.

    .PARAMETER Force
        Optional switch. When used alone, replaces all snippets with the backup.
        When used with -Merge, existing local snippets are overwritten on conflict.

    .EXAMPLE
        Import-SnipCollection -Path C:\Backups\my-snips.zip

        Restores snippets from the backup. Aborts if snippets already exist.

    .EXAMPLE
        Import-SnipCollection -Path C:\Backups\my-snips.zip -Merge

        Adds new snippets from the backup; existing local snippets are unaffected.

    .EXAMPLE
        Import-SnipCollection -Path C:\Backups\my-snips.zip -Force

        Replaces all local snippets with the backup contents.

    .EXAMPLE
        Import-SnipCollection -Path C:\Backups\my-snips.zip -Merge -Force

        Imports all backup snippets, overwriting local snippets on any conflict.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a summary of imported snippets to the host.

    .NOTES
        The archive is extracted to a temporary directory which is removed
        automatically after the import completes or on error.
        Supports -WhatIf via SupportsShouldProcess on Force (non-Merge) mode.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Path to the PSSnips backup ZIP')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [switch]$Merge,
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg

    if (-not (Test-Path $Path)) {
        Write-Error "ZIP file not found: $Path" -ErrorAction Continue; return
    }

    $extractDir = Join-Path $env:TEMP "pssnips_import_$([System.IO.Path]::GetRandomFileName())"
    try {
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        Expand-Archive -Path $Path -DestinationPath $extractDir -Force -ErrorAction Stop

        # Locate index.json — may be at root or nested one level deep
        $backupIdxPath = Join-Path $extractDir 'index.json'
        if (-not (Test-Path $backupIdxPath)) {
            $found = @(Get-ChildItem $extractDir -Filter 'index.json' -Recurse -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) { $backupIdxPath = $found[0].FullName }
        }

        $backupIdx = if ($backupIdxPath -and (Test-Path $backupIdxPath)) {
            $raw = Get-Content $backupIdxPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($raw) { $raw | ConvertFrom-Json -AsHashtable } else { @{ snippets = @{} } }
        } else { @{ snippets = @{} } }
        if (-not $backupIdx.ContainsKey('snippets')) { $backupIdx['snippets'] = @{} }

        # Locate the backup snippets directory
        $backupSnipDir = Join-Path $extractDir 'snippets'
        if (-not (Test-Path $backupSnipDir)) { $backupSnipDir = $extractDir }

        # Guard: warn if existing snippets and no merge/force specified
        $existingSnips = @(Get-ChildItem $cfg.SnippetsDir -File -ErrorAction SilentlyContinue)
        if ($existingSnips.Count -gt 0 -and -not $Merge -and -not $Force) {
            script:Out-Warn "Snippets directory already has $($existingSnips.Count) file(s). Use -Merge or -Force."
            return
        }

        $importCount = 0

        if ($Merge) {
            $localIdx = script:LoadIdx
            foreach ($snipName in @($backupIdx.snippets.Keys)) {
                # Skip conflict unless -Force
                if ($localIdx.snippets.ContainsKey($snipName) -and -not $Force) { continue }

                $lang    = $backupIdx.snippets[$snipName]['language']
                $srcFile = Join-Path $backupSnipDir "$snipName.$lang"
                if (-not (Test-Path $srcFile)) {
                    $found = @(Get-ChildItem $backupSnipDir -Filter "$snipName.*" -ErrorAction SilentlyContinue)
                    if ($found.Count -gt 0) { $srcFile = $found[0].FullName } else { $srcFile = '' }
                }
                if ($srcFile -and (Test-Path $srcFile)) {
                    Copy-Item $srcFile (Join-Path $cfg.SnippetsDir (Split-Path $srcFile -Leaf)) -Force
                    $localIdx.snippets[$snipName] = $backupIdx.snippets[$snipName]
                    $importCount++
                }
            }
            script:SaveIdx -Idx $localIdx
        } else {
            # Force mode: replace everything
            if ($PSCmdlet.ShouldProcess($cfg.SnippetsDir, 'Replace all snippets from backup')) {
                $backupFiles = @(Get-ChildItem $backupSnipDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch '^(index|config)\.json$' })
                foreach ($f in $backupFiles) {
                    Copy-Item $f.FullName (Join-Path $cfg.SnippetsDir $f.Name) -Force
                    $importCount++
                }
                script:SaveIdx -Idx $backupIdx
            }
        }

        script:Out-OK "$importCount snippet(s) imported from backup."
    } finally {
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

#endregion

#region ─── GitHub Gist ──────────────────────────────────────────────────────
# Functions that interact with the GitHub Gist API.
# All API calls require a GitHub personal access token with the 'gist' scope,
# set via Set-SnipConfig -GitHubToken or the $env:GITHUB_TOKEN environment variable.

function Get-GistList {
    <#
    .SYNOPSIS
        Lists GitHub Gists for the authenticated user or a specified GitHub username.

    .DESCRIPTION
        Calls the GitHub Gists API to retrieve a list of Gists and displays them in a
        formatted table showing the Gist ID, description, and file names. The number
        of results is controlled by -Count (default 30, max 100 per API call). Use
        -Filter to restrict results to Gists whose description or file names contain
        the given substring. Returns the raw API response objects for pipeline use.

    .PARAMETER Filter
        Optional. A substring to match against Gist descriptions and file names.
        Case-insensitive.

    .PARAMETER Count
        Optional. Maximum number of Gists to retrieve per API request. Default: 30.

    .PARAMETER Username
        Optional. Retrieve Gists for a different GitHub user. When omitted, defaults
        to the configured GitHubUsername, or the authenticated user's Gists.

    .EXAMPLE
        Get-GistList

        Lists the 30 most recent Gists for the configured user.

    .EXAMPLE
        Get-GistList -Filter 'deploy' -Count 50

        Lists up to 50 Gists whose description or file name contains 'deploy'.

    .EXAMPLE
        Get-GistList -Username octocat

        Lists public Gists for the GitHub user 'octocat'.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Object[]
        Returns the deserialized Gist API response objects. Each object contains id,
        description, html_url, files, and other GitHub API fields.

    .NOTES
        Requires a GitHub PAT with the 'gist' scope.
        Set via: Set-SnipConfig -GitHubToken 'ghp_...'  or  $env:GITHUB_TOKEN
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Filter   = '',
        [uint32]$Count    = 30,
        [string]$Username = ''
    )
    $cfg  = script:LoadCfg
    $user = if ($Username) { $Username } elseif ($cfg.GitHubUsername) { $cfg.GitHubUsername } else { '' }
    $ep   = if ($user) { "users/$user/gists?per_page=$Count" } else { "gists?per_page=$Count" }
    try {
        $gists = @(script:CallGitHub -Endpoint $ep)
    } catch { Write-Error "GitHub API error: $_" -ErrorAction Continue; return }

    if ($Filter) {
        $gists = $gists | Where-Object {
            $_.description -like "*$Filter*" -or
            ($_.files.PSObject.Properties.Name | Where-Object { $_ -like "*$Filter*" })
        }
    }
    if (-not $gists) { script:Out-Info "No gists found."; return }

    Write-Host ""
    Write-Host ("  {0,-34} {1,-38} {2}" -f 'GIST ID','DESCRIPTION','FILES') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 86)" -ForegroundColor DarkGray
    foreach ($g in $gists) {
        $files = ($g.files.PSObject.Properties.Name) -join ', '
        if ($files.Length -gt 30) { $files = $files.Substring(0,27) + '...' }
        $desc  = if ($g.description) { $g.description } else { '(no description)' }
        if ($desc.Length -gt 36) { $desc = $desc.Substring(0,33) + '...' }
        Write-Host ("  {0,-34} " -f $g.id) -ForegroundColor DarkYellow -NoNewline
        Write-Host ("{0,-38} {1}" -f $desc, $files) -ForegroundColor Gray
    }
    Write-Host ""
    return $gists
}

function Get-Gist {
    <#
    .SYNOPSIS
        Displays the full content of a GitHub Gist including all its files.

    .DESCRIPTION
        Fetches a specific Gist from the GitHub API by ID and prints each file's
        content to the terminal with syntax-coloured headers. If a file is marked
        truncated in the API response, the raw_url is fetched separately to retrieve
        the full content. Returns the raw Gist API object for pipeline use.

    .PARAMETER GistId
        Mandatory. The GitHub Gist ID (32-character hex string) to retrieve.

    .EXAMPLE
        Get-Gist abc123def456abc123def456abc1234567

        Fetches and displays all files in the specified Gist.

    .EXAMPLE
        $gist = Get-Gist abc123def456abc123def456abc1234567
        $gist.html_url

        Retrieves the Gist object and accesses its HTML URL.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Object
        Returns the deserialized Gist object from the GitHub API containing id,
        description, html_url, files, owner, and related metadata.

    .NOTES
        Requires a GitHub PAT with the 'gist' scope.
        Truncated file content (>1 MB) is fetched via an additional web request
        to the file's raw_url.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'GitHub Gist ID')]
        [ValidateNotNullOrEmpty()]
        [string]$GistId)
    try { $gist = script:CallGitHub -Endpoint "gists/$GistId" }
    catch { Write-Error "Failed to fetch gist: $_" -ErrorAction Continue; return }

    Write-Host ""
    Write-Host "  Gist: $GistId" -ForegroundColor Cyan
    if ($gist.description) { Write-Host "  $($gist.description)" -ForegroundColor Gray }
    Write-Host "  $($gist.html_url)" -ForegroundColor DarkCyan
    Write-Host ""

    foreach ($fn in $gist.files.PSObject.Properties.Name) {
        $f   = $gist.files.$fn
        $ext = [System.IO.Path]::GetExtension($fn).TrimStart('.')
        $c   = script:LangColor -ext $ext
        Write-Host "  ── $fn ──" -ForegroundColor $c
        $body = if ($f.truncated) { (Invoke-RestMethod -Uri $f.raw_url).ToString() } else { $f.content }
        Write-Host $body
        Write-Host ""
    }
    return $gist
}

function Import-Gist {
    <#
    .SYNOPSIS
        Downloads a GitHub Gist and saves it as one or more local snippets.

    .DESCRIPTION
        Fetches the specified Gist from GitHub and writes each selected file to the
        configured SnippetsDir. The snippet language is inferred from the file
        extension. Multi-file Gists prompt interactively for which file to import
        unless -All is specified. If a snippet with the derived name already exists,
        a numeric suffix is appended to avoid collision (unless -Force is used).
        The Gist ID and URL are stored in the snippet's index metadata to enable
        future sync operations.

    .PARAMETER GistId
        Mandatory. The GitHub Gist ID to import.

    .PARAMETER Name
        Optional. Override the local snippet name. Only applies when importing a
        single file; ignored when -All is used.

    .PARAMETER FileName
        Optional. Imports only the specified file from a multi-file Gist.

    .PARAMETER All
        Optional switch. Imports all files from the Gist as separate snippets.

    .PARAMETER Force
        Optional switch. Overwrites existing snippets with the same name.

    .EXAMPLE
        Import-Gist abc123def456abc123def456abc1234567

        Imports the first (or only) file from the Gist as a local snippet.

    .EXAMPLE
        Import-Gist abc123def456abc123def456abc1234567 -Name my-local-name

        Imports the Gist and saves it with the local name 'my-local-name'.

    .EXAMPLE
        Import-Gist abc123def456abc123def456abc1234567 -All

        Imports every file in the Gist as individual snippets.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message per imported snippet.

    .NOTES
        When -Name is not supplied, the snippet name is derived from the Gist
        file name (without extension). For multi-file imports with -All, each file
        is stored using its original file base name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'GitHub Gist ID to import')]
        [ValidateNotNullOrEmpty()]
        [string]$GistId,
        [string]$Name      = '',
        [string]$FileName  = '',
        [switch]$All,
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg
    try { $gist = script:CallGitHub -Endpoint "gists/$GistId" }
    catch { Write-Error "Failed to fetch gist: $_" -ErrorAction Continue; return }

    $fileNames = @($gist.files.PSObject.Properties.Name)

    # Multi-file prompt when needed
    if ($fileNames.Count -gt 1 -and -not $All -and -not $FileName) {
        Write-Host "`n  Gist has $($fileNames.Count) files:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $fileNames.Count; $i++) { Write-Host "    [$i] $($fileNames[$i])" -ForegroundColor Gray }
        $choice = Read-Host "`n  File number to import (or 'all')"
        if ($choice -eq 'all') { $All = $true } else { $FileName = $fileNames[[int]$choice] }
    }

    $toImport = if ($All) { $fileNames } elseif ($FileName) { @($FileName) } else { @($fileNames[0]) }
    $idx = script:LoadIdx

    foreach ($fn in $toImport) {
        $f        = $gist.files.$fn
        $ext      = [System.IO.Path]::GetExtension($fn).TrimStart('.')
        $snipName = if ($Name -and $toImport.Count -eq 1) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($fn) }

        # Deduplicate name
        if ($idx.snippets.ContainsKey($snipName) -and -not $Force) {
            $base = $snipName; $n = 1
            while ($idx.snippets.ContainsKey($snipName)) { $snipName = "$base-$n"; $n++ }
        }

        $body = if ($f.truncated) { (Invoke-RestMethod -Uri $f.raw_url).ToString() } else { $f.content }
        Set-Content (Join-Path $cfg.SnippetsDir "$snipName.$ext") -Value $body -Encoding UTF8

        $idx.snippets[$snipName] = @{
            name = $snipName; description = $gist.description; language = $ext
            tags = @(); created = (Get-Date -Format 'o'); modified = (Get-Date -Format 'o')
            gistId = $GistId; gistUrl = $gist.html_url
        }
        script:Out-OK "Imported '$snipName' ($ext)."
    }
    script:SaveIdx -Idx $idx
}

function Export-Gist {
    <#
    .SYNOPSIS
        Exports a local snippet to GitHub as a new or updated Gist.

    .DESCRIPTION
        Reads the snippet file and its metadata, then creates a new GitHub Gist via
        POST or updates the existing linked Gist via PATCH. The decision is based on
        whether the snippet's 'gistId' field in the index is set. After a successful
        API call, the Gist ID and URL are written back to index.json so that future
        calls update the same Gist. New Gists are secret by default; use -Public to
        create a publicly visible Gist.

    .PARAMETER Name
        Mandatory. The name of the local snippet to export.

    .PARAMETER Description
        Optional. A description for the Gist. Falls back to the snippet's description,
        then the snippet name if not provided.

    .PARAMETER Public
        Optional switch. Creates a public Gist. Default is a secret Gist.

    .EXAMPLE
        Export-Gist my-snippet

        Creates a secret Gist from 'my-snippet' or updates the linked one.

    .EXAMPLE
        Export-Gist my-snippet -Description 'Handy deploy script' -Public

        Creates or updates a public Gist with a specific description.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes the resulting Gist URL to the host on success.

    .NOTES
        Requires a GitHub PAT with the 'gist' scope.
        If the snippet has a gistId in the index, the Gist is updated (PATCH).
        If not, a new Gist is created (POST) and the ID is saved to the index.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to export as a Gist')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Description = '',
        [switch]$Public
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $meta    = $idx.snippets[$Name]
    $path    = script:FindFile -Name $Name
    $content = Get-Content $path -Raw -Encoding UTF8
    $fn      = "$Name.$($meta.language)"
    $desc    = if ($Description) { $Description } elseif ($meta.description) { $meta.description } else { $Name }

    $body = @{
        description = $desc
        public      = [bool]$Public
        files       = @{ $fn = @{ content = $content } }
    }
    try {
        $result = if ($meta.gistId) {
            script:CallGitHub -Endpoint "gists/$($meta.gistId)" -Method 'PATCH' -Body $body
        } else {
            script:CallGitHub -Endpoint 'gists' -Method 'POST' -Body $body
        }
        $idx.snippets[$Name]['gistId']  = $result.id
        $idx.snippets[$Name]['gistUrl'] = $result.html_url
        script:SaveIdx -Idx $idx
        script:Out-OK "Gist $(if ($meta.gistId) {'updated'} else {'created'}): $($result.html_url)"
    } catch { Write-Error "Failed to export gist: $_" -ErrorAction Continue }
}

function Invoke-Gist {
    <#
    .SYNOPSIS
        Downloads and executes a GitHub Gist file without saving it locally.

    .DESCRIPTION
        Fetches a Gist from GitHub, writes the selected file to a temporary path in
        $env:TEMP, executes it with the appropriate language runner, and then deletes
        the temporary file in a finally block. The runner selection follows the same
        logic as Invoke-Snip (ps1, py, js, bat/cmd, sh, rb, go). Supports -WhatIf
        via ShouldProcess — with -WhatIf the file is not written or executed.
        When the Gist has multiple files, the first file matching a known runnable
        extension is selected automatically; use -FileName to specify explicitly.

    .PARAMETER GistId
        Mandatory. The GitHub Gist ID to fetch and run.

    .PARAMETER FileName
        Optional. The specific file within the Gist to run. When omitted, the first
        file with a known runnable extension is selected.

    .PARAMETER ArgumentList
        Optional. Arguments forwarded to the language runner after the file path.

    .EXAMPLE
        Invoke-Gist abc123def456abc123def456abc1234567

        Fetches and executes the runnable file in the specified Gist.

    .EXAMPLE
        Invoke-Gist abc123def456abc123def456abc1234567 -FileName script.ps1

        Runs the named file from the Gist.

    .EXAMPLE
        Invoke-Gist abc123def456abc123def456abc1234567 -WhatIf

        Shows what would be executed without actually running it.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Variable. Output depends on the language runner.

    .NOTES
        The temporary file is always deleted after execution (or on error) via a
        try/finally block. The temp file is placed in $env:TEMP with a random name.
        Requires a GitHub PAT with the 'gist' scope.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'GitHub Gist ID to run')]
        [ValidateNotNullOrEmpty()]
        [string]$GistId,
        [string]  $FileName    = '',
        [string[]]$ArgumentList = @()
    )
    try { $gist = script:CallGitHub -Endpoint "gists/$GistId" }
    catch { Write-Error "Failed to fetch gist: $_" -ErrorAction Continue; return }

    $fileNames = @($gist.files.PSObject.Properties.Name)
    $target = if ($FileName) { $FileName }
              elseif ($fileNames.Count -eq 1) { $fileNames[0] }
              else { $fileNames | Where-Object { $_ -match '\.(ps1|py|js|bat|cmd|sh|rb|go)$' } | Select-Object -First 1 }

    if (-not $target) { Write-Error "Cannot determine runnable file. Use -FileName." -ErrorAction Continue; return }

    $f    = $gist.files.$target
    $ext  = [System.IO.Path]::GetExtension($target).TrimStart('.').ToLower()
    $body = if ($f.truncated) { (Invoke-RestMethod -Uri $f.raw_url).ToString() } else { $f.content }

    script:Out-Info "Running gist $GistId → $target"

    if ($PSCmdlet.ShouldProcess($target, "Execute gist file")) {
        $tmp = Join-Path $env:TEMP "pssnips_$([System.IO.Path]::GetRandomFileName()).$ext"
        try {
            Set-Content $tmp -Value $body -Encoding UTF8 -ErrorAction Stop
            # Template variable substitution
            $gistPlaceholders = @([regex]::Matches($body, '\{\{([A-Z0-9_]+)\}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
                ForEach-Object { $_.Groups[1].Value.ToUpper() } | Select-Object -Unique)
            if ($gistPlaceholders.Count -gt 0) {
                $gistVarContent = Get-Content $tmp -Raw -Encoding UTF8
                foreach ($ph in $gistPlaceholders) {
                    $val = Read-Host "  Value for {{$ph}}"
                    $gistVarContent = $gistVarContent -replace [regex]::Escape("{{$ph}}"), $val
                }
                Set-Content $tmp -Value $gistVarContent -Encoding UTF8
            }
            switch ($ext) {
                { $_ -in 'ps1','psm1' }  { & $tmp @ArgumentList }
                'py'  { $py = @('python','python3') | Where-Object { Get-Command $_ -EA 0 } | Select-Object -First 1; if ($py) { & $py $tmp @ArgumentList } }
                'js'  { if (Get-Command node -EA 0) { & node $tmp @ArgumentList } }
                { $_ -in 'bat','cmd' }   { & cmd /c $tmp @ArgumentList }
                'sh'  { if (Get-Command bash -EA 0) { & bash $tmp @ArgumentList } else { & wsl bash $tmp @ArgumentList } }
                'rb'  { if (Get-Command ruby -EA 0) { & ruby $tmp @ArgumentList } }
                'go'  { if (Get-Command go   -EA 0) { & go run $tmp @ArgumentList } }
                default { script:Out-Warn "No runner for '.$ext'. Saved to: $tmp"; return }
            }
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -EA SilentlyContinue }
        }
    }
}

function Sync-Gist {
    <#
    .SYNOPSIS
        Synchronises a local snippet with its linked GitHub Gist (pull or push).

    .DESCRIPTION
        Bi-directional sync between a local snippet and the GitHub Gist it was
        linked to via Export-Gist or Import-Gist. By default (pull mode) the local
        snippet file is overwritten with the latest content from GitHub. With -Push,
        the local file's current content is uploaded to GitHub, updating the Gist.
        The snippet must already have a linked gistId; run Export-Gist first to
        establish the link.

    .PARAMETER Name
        Mandatory. The name of the local snippet to synchronise.

    .PARAMETER Push
        Optional switch. Pushes the local snippet content to GitHub (update Gist).
        Without this switch, the default is to pull (download from GitHub).

    .EXAMPLE
        Sync-Gist my-snippet

        Pulls the latest Gist content from GitHub into the local snippet file.

    .EXAMPLE
        Sync-Gist my-snippet -Push

        Uploads the current local snippet content to the linked GitHub Gist.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a status message to the host.

    .NOTES
        Pull mode calls Import-Gist -Force which overwrites the local file.
        Push mode calls Export-Gist which PATCHes the existing Gist.
        The snippet must have a non-null gistId in the index. If not, an error
        is displayed directing the user to run Export-Gist first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to sync with its Gist')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Push
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }
    if (-not $idx.snippets[$Name].gistId)      { Write-Error "'$Name' has no linked gist. Run Export-Gist first." -ErrorAction Continue; return }
    if ($Push) { Export-Gist -Name $Name }
    else       { Import-Gist -GistId $idx.snippets[$Name].gistId -Name $Name -Force }
}

#endregion

#region ─── GitLab Snippets ─────────────────────────────────────────────────

function Get-GitLabSnipList {
    <#
    .SYNOPSIS
        Lists GitLab snippets for the authenticated user.
    .DESCRIPTION
        Calls the GitLab Snippets API (GET /api/v4/snippets) and displays a formatted
        table of snippets showing ID, Title, Visibility, and FileName.
    .PARAMETER Filter
        Optional substring to match against title and file_name.
    .PARAMETER Count
        Optional. Maximum number of snippets to retrieve. Default: 30.
    .EXAMPLE
        Get-GitLabSnipList
    .EXAMPLE
        Get-GitLabSnipList -Filter 'deploy' -Count 50
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Filter = '',
        [uint32]$Count  = 30
    )
    try {
        $snips = @(script:CallGitLab -Endpoint "snippets?per_page=$Count")
    } catch { Write-Error "GitLab API error: $_" -ErrorAction Continue; return }

    if ($Filter) {
        $snips = @($snips | Where-Object { $_.title -like "*$Filter*" -or $_.file_name -like "*$Filter*" })
    }
    if (-not $snips -or $snips.Count -eq 0) { script:Out-Info "No GitLab snippets found."; return }

    Write-Host ""
    Write-Host ("  {0,-10} {1,-40} {2,-10} {3}" -f 'ID','TITLE','VISIBILITY','FILENAME') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 80)" -ForegroundColor DarkGray
    foreach ($s in $snips) {
        $fn = if ($s.file_name) { $s.file_name } else { '' }
        Write-Host ("  {0,-10} {1,-40} {2,-10} {3}" -f $s.id, $s.title, $s.visibility, $fn) -ForegroundColor Gray
    }
    Write-Host ""
    return $snips
}

function Get-GitLabSnip {
    <#
    .SYNOPSIS
        Fetches and displays a specific GitLab snippet by ID.
    .DESCRIPTION
        Calls GET /api/v4/snippets/<id> and GET /api/v4/snippets/<id>/raw,
        returning the snippet object with RawContent added.
    .PARAMETER SnipId
        Mandatory. The GitLab snippet ID.
    .EXAMPLE
        Get-GitLabSnip 12345
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='GitLab snippet ID')]
        [ValidateNotNullOrEmpty()]
        [string]$SnipId
    )
    try {
        $snip = script:CallGitLab -Endpoint "snippets/$SnipId"
        $raw  = script:CallGitLab -Endpoint "snippets/$SnipId/raw"
    } catch { Write-Error "GitLab API error: $_" -ErrorAction Continue; return }

    $snip | Add-Member -NotePropertyName RawContent -NotePropertyValue $raw -Force
    Write-Host ""
    Write-Host ("  Snippet: {0} (ID: {1})" -f $snip.title, $SnipId) -ForegroundColor Cyan
    if ($snip.description) { Write-Host "  $($snip.description)" -ForegroundColor Gray }
    Write-Host "  $($snip.web_url)" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host $raw
    Write-Host ""
    return $snip
}

function Import-GitLabSnip {
    <#
    .SYNOPSIS
        Downloads a GitLab snippet and saves it as a local snippet.
    .DESCRIPTION
        Fetches the raw content from /api/v4/snippets/<id>/raw and metadata from
        /api/v4/snippets/<id>, then saves to local snippets dir and registers in
        the index with gitlabId and gitlabUrl fields.
    .PARAMETER SnipId
        Mandatory. The GitLab snippet ID to import.
    .PARAMETER Name
        Optional. Override the local snippet name.
    .PARAMETER Force
        Optional switch. Overwrites existing snippet with the same name.
    .EXAMPLE
        Import-GitLabSnip 12345
    .EXAMPLE
        Import-GitLabSnip 12345 -Name my-local-name -Force
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
        The gitlabId and gitlabUrl are stored in the index for future sync.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='GitLab snippet ID to import')]
        [ValidateNotNullOrEmpty()]
        [string]$SnipId,
        [string]$Name  = '',
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg
    try {
        $meta = script:CallGitLab -Endpoint "snippets/$SnipId"
        $raw  = script:CallGitLab -Endpoint "snippets/$SnipId/raw"
    } catch { Write-Error "GitLab API error: $_" -ErrorAction Continue; return }

    $fn       = if ($meta.file_name) { $meta.file_name } else { 'snippet.txt' }
    $ext      = [System.IO.Path]::GetExtension($fn).TrimStart('.')
    if (-not $ext) { $ext = 'txt' }
    $snipName = if ($Name) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($fn) }

    $idx = script:LoadIdx
    # Deduplicate name
    if ($idx.snippets.ContainsKey($snipName) -and -not $Force) {
        $base = $snipName; $n = 1
        while ($idx.snippets.ContainsKey($snipName)) { $snipName = "$base-$n"; $n++ }
    }

    Set-Content (Join-Path $cfg.SnippetsDir "$snipName.$ext") -Value $raw -Encoding UTF8
    $idx.snippets[$snipName] = @{
        name        = $snipName
        description = if ($meta.description) { $meta.description } else { $meta.title }
        language    = $ext
        tags        = @()
        created     = (Get-Date -Format 'o')
        modified    = (Get-Date -Format 'o')
        gistId      = $null
        gistUrl     = $null
        gitlabId    = $SnipId
        gitlabUrl   = if ($meta.web_url) { $meta.web_url } else { '' }
        contentHash = script:GetContentHash -Content $raw
    }
    script:SaveIdx -Idx $idx
    script:Out-OK "Imported GitLab snippet '$snipName' ($ext)."
}

function Export-GitLabSnip {
    <#
    .SYNOPSIS
        Exports a local snippet to GitLab as a new or updated snippet.
    .DESCRIPTION
        Creates (POST /api/v4/snippets) or updates (PUT /api/v4/snippets/<id>) a
        GitLab snippet. After success, saves gitlabId and gitlabUrl to the index.
    .PARAMETER Name
        Mandatory. The local snippet name to export.
    .PARAMETER Description
        Optional. Description for the GitLab snippet.
    .PARAMETER Visibility
        Optional. 'public', 'internal', or 'private'. Default: 'private'.
    .EXAMPLE
        Export-GitLabSnip my-snippet
    .EXAMPLE
        Export-GitLabSnip my-snippet -Description 'Deploy script' -Visibility internal
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
        If snippet already has a gitlabId, the existing GitLab snippet is updated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Local snippet name to export')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Description = '',
        [ValidateSet('public','internal','private')]
        [string]$Visibility  = 'private'
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $meta    = $idx.snippets[$Name]
    $path    = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet file for '$Name' not found." -ErrorAction Continue; return }
    $content = Get-Content $path -Raw -Encoding UTF8
    $fn      = "$Name.$($meta.language)"
    $desc    = if ($Description) { $Description } elseif ($meta.description) { $meta.description } else { $Name }

    $body = @{
        title       = $Name
        description = $desc
        visibility  = $Visibility
        files       = @(@{ file_path = $fn; content = $content })
    }
    try {
        $glId = if ($meta.ContainsKey('gitlabId') -and $meta.gitlabId) { $meta.gitlabId } else { $null }
        $result = if ($glId) {
            script:CallGitLab -Endpoint "snippets/$glId" -Method 'PUT' -Body $body
        } else {
            script:CallGitLab -Endpoint 'snippets' -Method 'POST' -Body $body
        }
        $idx.snippets[$Name]['gitlabId']  = $result.id
        $idx.snippets[$Name]['gitlabUrl'] = if ($result.web_url) { $result.web_url } else { '' }
        script:SaveIdx -Idx $idx
        script:Out-OK "GitLab snippet $(if ($glId) {'updated'} else {'created'}): $($result.web_url)"
    } catch { Write-Error "Failed to export to GitLab: $_" -ErrorAction Continue }
}

#endregion

#region ─── Shared Storage ───────────────────────────────────────────────────

function Publish-Snip {
    <#
    .SYNOPSIS
        Copies a local snippet to the configured shared storage directory.
    .DESCRIPTION
        Copies the snippet file to SharedSnippetsDir and updates shared-index.json
        in the shared directory with the snippet's metadata.
    .PARAMETER Name
        Mandatory. The local snippet name to publish.
    .PARAMETER Force
        Optional switch. Overwrites the snippet in shared storage if it already exists.
    .EXAMPLE
        Publish-Snip my-snippet
    .EXAMPLE
        Publish-Snip my-snippet -Force
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        SharedSnippetsDir must be set via Set-SnipConfig -SharedSnippetsDir <path>.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Local snippet name to publish to shared storage')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Force
    )
    script:InitEnv
    $sharedDir = script:GetSharedDir
    if (-not $sharedDir) { return }

    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $srcPath = script:FindFile -Name $Name
    if (-not $srcPath -or -not (Test-Path $srcPath)) { Write-Error "Snippet file for '$Name' not found." -ErrorAction Continue; return }

    $destFile = Join-Path $sharedDir (Split-Path $srcPath -Leaf)
    if ((Test-Path $destFile) -and -not $Force) {
        script:Out-Warn "Snippet '$Name' already exists in shared storage. Use -Force to overwrite."
        return
    }

    if ($PSCmdlet.ShouldProcess($destFile, "Publish snippet '$Name'")) {
        Copy-Item $srcPath $destFile -Force

        # Update shared-index.json with advisory lock + atomic write
        $sharedIdxFile = Join-Path $sharedDir 'shared-index.json'
        $sharedIdx = if (Test-Path $sharedIdxFile) {
            try {
                $raw = Get-Content $sharedIdxFile -Raw -Encoding UTF8 -ErrorAction Stop
                if ($raw) {
                    $si = $raw | ConvertFrom-Json -AsHashtable
                    if (-not $si.ContainsKey('snippets')) { $si['snippets'] = @{} }
                    $si
                } else { @{ snippets = @{} } }
            } catch { @{ snippets = @{} } }
        } else { @{ snippets = @{} } }

        $sharedIdx['snippets'][$Name] = $idx.snippets[$Name]

        $sharedLockFile = "$sharedIdxFile.lock"
        $sharedLock = script:AcquireLock -LockFile $sharedLockFile
        try {
            $sharedTmp = "$sharedIdxFile.tmp"
            $sharedIdx | ConvertTo-Json -Depth 10 | Set-Content -Path $sharedTmp -Encoding UTF8
            Move-Item -Path $sharedTmp -Destination $sharedIdxFile -Force
        } finally {
            script:ReleaseLock -Stream $sharedLock -LockFile $sharedLockFile
            if (Test-Path "$sharedIdxFile.tmp") { Remove-Item "$sharedIdxFile.tmp" -ErrorAction SilentlyContinue }
        }
        script:Out-OK "Published '$Name' to shared storage: $destFile"
    }
}

function Sync-SharedSnips {
    <#
    .SYNOPSIS
        Imports snippets from shared storage into the local snippet collection.
    .DESCRIPTION
        Reads shared-index.json from SharedSnippetsDir and copies any snippet not
        present locally (or all snippets with -Force) into the local collection.
    .PARAMETER Force
        Optional switch. Imports all shared snippets, overwriting local ones.
    .EXAMPLE
        Sync-SharedSnips
    .EXAMPLE
        Sync-SharedSnips -Force
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        SharedSnippetsDir must be set via Set-SnipConfig -SharedSnippetsDir <path>.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$Force
    )
    script:InitEnv
    $sharedDir = script:GetSharedDir
    if (-not $sharedDir) { return }

    $sharedIdxFile = Join-Path $sharedDir 'shared-index.json'
    if (-not (Test-Path $sharedIdxFile)) {
        script:Out-Info "No shared-index.json found at $sharedDir."
        return
    }

    $sharedIdx = try {
        $raw = Get-Content $sharedIdxFile -Raw -Encoding UTF8 -ErrorAction Stop
        if ($raw) {
            $si = $raw | ConvertFrom-Json -AsHashtable
            if (-not $si.ContainsKey('snippets')) { $si['snippets'] = @{} }
            $si
        } else { @{ snippets = @{} } }
    } catch { @{ snippets = @{} } }

    $cfg      = script:LoadCfg
    $localIdx = script:LoadIdx
    $synced   = 0

    foreach ($snipName in @($sharedIdx['snippets'].Keys)) {
        if ($localIdx.snippets.ContainsKey($snipName) -and -not $Force) { continue }
        $meta    = $sharedIdx['snippets'][$snipName]
        $lang    = $meta['language']
        $srcFile = Join-Path $sharedDir "$snipName.$lang"
        if (-not (Test-Path $srcFile)) {
            $found = @(Get-ChildItem $sharedDir -Filter "$snipName.*" -ErrorAction SilentlyContinue)
            if ($found.Count -gt 0) { $srcFile = $found[0].FullName } else { continue }
        }
        if ($PSCmdlet.ShouldProcess($snipName, 'Sync snippet from shared storage')) {
            $destFile = Join-Path $cfg.SnippetsDir (Split-Path $srcFile -Leaf)
            Copy-Item $srcFile $destFile -Force
            $localIdx.snippets[$snipName] = $meta
            $synced++
        }
    }
    script:SaveIdx -Idx $localIdx
    script:Out-OK "Synced $synced new snippet(s) from shared storage."
}

#endregion

#region ─── Profile Integration ─────────────────────────────────────────────

function Install-PSSnips {
    <#
    .SYNOPSIS
        Adds PSSnips to a PowerShell profile so it loads automatically.
    .DESCRIPTION
        Locates the specified PowerShell profile file, creates it if it doesn't exist,
        and appends an Import-Module line for PSSnips if not already present.
    .PARAMETER Scope
        The profile scope to modify. Default: CurrentUserCurrentHost.
        Valid values: CurrentUserCurrentHost, CurrentUserAllHosts,
                      AllUsersCurrentHost, AllUsersAllHosts.
    .PARAMETER Force
        Optional switch. Adds the import line even if PSSnips is already in the profile.
    .EXAMPLE
        Install-PSSnips
    .EXAMPLE
        Install-PSSnips -Scope CurrentUserAllHosts
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        After installation, restart PowerShell or dot-source the profile file.
        Supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('CurrentUserCurrentHost','CurrentUserAllHosts','AllUsersCurrentHost','AllUsersAllHosts')]
        [string]$Scope = 'CurrentUserCurrentHost',
        [switch]$Force
    )
    script:InitEnv
    $profilePath = $PROFILE.$Scope
    $importLine  = "Import-Module '$($MyInvocation.MyCommand.Module.Path)'"

    if ($PSCmdlet.ShouldProcess($profilePath, "Add PSSnips import")) {
        # Create profile if it doesn't exist
        if (-not (Test-Path $profilePath)) {
            $profileDir = Split-Path $profilePath -Parent
            if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
            Set-Content $profilePath -Value "# PowerShell Profile`n" -Encoding UTF8
        }

        # Check if already present
        $existing = Select-String -Path $profilePath -Pattern 'PSSnips' -ErrorAction SilentlyContinue
        if ($existing -and -not $Force) {
            script:Out-Info "PSSnips already in profile at $profilePath"
            return
        }

        # Append import line
        Add-Content $profilePath -Value "`n$importLine" -Encoding UTF8
        script:Out-OK "PSSnips added to profile: $profilePath"
        script:Out-Info "Restart PowerShell or run: . `"$profilePath`""
    }
}

function Uninstall-PSSnips {
    <#
    .SYNOPSIS
        Removes PSSnips from a PowerShell profile.
    .DESCRIPTION
        Reads the specified profile file and removes any lines containing 'PSSnips',
        then writes the cleaned content back.
    .PARAMETER Scope
        The profile scope to modify. Default: CurrentUserCurrentHost.
    .EXAMPLE
        Uninstall-PSSnips
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('CurrentUserCurrentHost','CurrentUserAllHosts','AllUsersCurrentHost','AllUsersAllHosts')]
        [string]$Scope = 'CurrentUserCurrentHost'
    )
    $profilePath = $PROFILE.$Scope
    if (-not (Test-Path $profilePath)) {
        script:Out-Info "Profile not found: $profilePath"
        return
    }
    if ($PSCmdlet.ShouldProcess($profilePath, "Remove PSSnips import")) {
        $lines   = @(Get-Content $profilePath -Encoding UTF8)
        $cleaned = @($lines | Where-Object { $_ -notmatch 'PSSnips' })
        Set-Content $profilePath -Value $cleaned -Encoding UTF8
        script:Out-OK "PSSnips removed from profile: $profilePath"
    }
}

#endregion

#region ─── Interactive TUI ──────────────────────────────────────────────────
# Full-screen terminal UI (TUI) built on raw console key input.
# Uses [Console]::SetCursorPosition for in-place screen redraws and
# $Host.UI.RawUI.ReadKey for single-keypress navigation without Enter.

function Start-SnipManager {
    <#
    .SYNOPSIS
        Launches the full-screen interactive terminal snippet manager (TUI).

    .DESCRIPTION
        Starts a full-screen text UI that displays a navigable list of snippets with
        real-time search filtering. The UI is drawn using [Console]::SetCursorPosition
        for in-place redraws without flickering. Navigation uses raw virtual key codes
        read via $Host.UI.RawUI.ReadKey:
          VK 38 (Up arrow)    - move selection up
          VK 40 (Down arrow)  - move selection down
          VK 13 (Enter)       - open detail view
          VK 39 (Right arrow) - open detail view
          VK 27 (Esc)         - return to list view from detail
          VK 37 (Left arrow)  - return to list view from detail
        Single-character commands (n, e, r, c, d, g, /) are handled in the default
        branch of the key switch. The cursor is hidden during TUI operation and
        restored in a finally block to ensure visibility is not lost on error.

    .EXAMPLE
        Start-SnipManager

        Launches the interactive TUI snippet manager.

    .EXAMPLE
        snip

        Equivalent shortcut: calling snip with no arguments starts the TUI.

    .INPUTS
        None.

    .OUTPUTS
        None. All interaction is through the console.

    .NOTES
        Requires an interactive host with RawUI support. Will not work correctly
        in non-interactive sessions (e.g., CI pipelines) or when stdout is
        redirected. The TUI shows up to 20 snippets per page; use [/] to filter
        when the collection exceeds 20 items.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    script:InitEnv

    $idx   = script:LoadIdx
    $sel   = 0
    $mode  = 'list'   # 'list' | 'detail'
    $query = ''
    $msg   = ''

    function Get-Filtered {
        param([hashtable]$Idx, [string]$q)
        $allItems = @(foreach ($n in ($Idx.snippets.Keys | Sort-Object)) {
            $m = $Idx.snippets[$n]
        # @($m.tags) guard: PS 5.1 may return a bare string for single-element arrays
            if (-not $q -or $n -like "*$q*" -or ($m.description -like "*$q*") -or
                ((@($m.tags) -join ',') -like "*$q*")) {
                $isPinned = $m.ContainsKey('pinned') -and $m['pinned'] -eq $true
                [pscustomobject]@{ Name = $n; Meta = $m; Pinned = $isPinned }
            }
        })
        # Pinned snippets float to the top
        $pinnedItems    = @($allItems | Where-Object { $_.Pinned })
        $unpinnedItems  = @($allItems | Where-Object { -not $_.Pinned })
        return @($pinnedItems) + @($unpinnedItems)
    }

    function Write-SnipList {
        param([array]$list, [int]$s, [string]$q, [string]$statusMsg)
        [Console]::SetCursorPosition(0,0)
        script:Out-Banner
        Write-Host ("  {0,-6} {1,-5} {2}" -f 'Keys','','Actions') -ForegroundColor DarkGray
        Write-Host "  [↑↓] Navigate  [Enter/→] View  [n] New  [e] Edit  [r] Run  [c] Copy  [d] Delete" -ForegroundColor DarkGray
        Write-Host "  [g] Export Gist  [/] Search  [q] Quit" -ForegroundColor DarkGray
        if ($q) { Write-Host ("  Filter: {0,-40}" -f $q) -ForegroundColor Yellow } else { Write-Host "  $(' ' * 50)" }
        Write-Host "  $('─' * 76)" -ForegroundColor DarkGray

        if ($list.Count -eq 0) {
            Write-Host "  (no snippets — press [n] to create one)$(' ' * 20)" -ForegroundColor DarkGray
        } else {
            $visible = [Math]::Min($list.Count, 20)
            for ($i = 0; $i -lt $visible; $i++) {
                $item  = $list[$i]
                $c     = script:LangColor -ext $item.Meta.language
                $gmark = if ($item.Meta.gistId) { ' [G]' } else { '    ' }
                $desc  = if ($item.Meta.description) { "  $($item.Meta.description)" } else { '' }
                $tags  = if (@($item.Meta.tags).Count -gt 0) { "  [$( (@($item.Meta.tags) -join ',') )]" } else { '' }
                $pin   = if ($item.Pinned) { '★ ' } else { '  ' }
                $row   = "{0}{1,-24} {2,-6}{3}{4}{5}" -f $pin, $item.Name, $item.Meta.language, $gmark, $desc, $tags
                if ($row.Length -gt 74) { $row = $row.Substring(0,71) + '...' }
                if ($i -eq $s) {
                    Write-Host ("  ► {0,-74}" -f $row) -BackgroundColor DarkBlue -ForegroundColor White
                } else {
                    Write-Host ("    " + $row + (' ' * [Math]::Max(0, 74 - $row.Length))) -ForegroundColor $c
                }
            }
            if ($list.Count -gt 20) { Write-Host "  ... and $($list.Count - 20) more. Use [/] to filter." -ForegroundColor DarkGray }
        }
        Write-Host "  $('─' * 76)" -ForegroundColor DarkGray
        if ($statusMsg) { Write-Host ("  {0,-76}" -f $statusMsg) -ForegroundColor Green } else { Write-Host (' ' * 80) }
        Write-Host "" 
    }

    function Write-SnipDetail {
        param([pscustomobject]$item)
        [Console]::SetCursorPosition(0,0)
        $c    = script:LangColor -ext $item.Meta.language
        $path = script:FindFile -Name $item.Name
        Write-Host ""
        Write-Host ("  ╔═ {0} ({1}) ═╗" -f $item.Name, $item.Meta.language) -ForegroundColor $c
        if ($item.Meta.description) { Write-Host "  $($item.Meta.description)" -ForegroundColor Gray }
        if ($item.Meta.gistUrl)     { Write-Host "  Gist: $($item.Meta.gistUrl)" -ForegroundColor DarkCyan }
        if (@($item.Meta.tags).Count -gt 0) { Write-Host "  Tags: $( (@($item.Meta.tags) -join ', '))" -ForegroundColor DarkGray }
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        if ($path -and (Test-Path $path)) {
            $lines = Get-Content $path -Encoding UTF8
            $shown = [Math]::Min($lines.Count, 30)
            for ($i = 0; $i -lt $shown; $i++) { Write-Host "  $($lines[$i])" }
            if ($lines.Count -gt 30) { Write-Host "  ... ($($lines.Count - 30) more lines)" -ForegroundColor DarkGray }
        }
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        Write-Host "  [e] Edit  [r] Run  [c] Copy  [g] Gist  [Esc/←] Back" -ForegroundColor DarkGray
        Write-Host (' ' * 80)
    }

    try {
        [Console]::CursorVisible = $false
        Clear-Host

        :outer while ($true) {
            $list = Get-Filtered -Idx $idx -q $query
        if ($null -eq $list) { $list = @() }
            if ($sel -ge $list.Count) { $sel = [Math]::Max(0, $list.Count - 1) }

            switch ($mode) {
                'list'   { Write-SnipList   -list $list -s $sel -q $query -statusMsg $msg }
                'detail' { if ($list.Count -gt 0) { Write-SnipDetail -item $list[$sel] } else { $mode = 'list' } }
            }
            $msg = ''

            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $vk  = $key.VirtualKeyCode
            $ch  = $key.Character

            if ($mode -eq 'list') {
                switch ($vk) {
                    38 { if ($sel -gt 0) { $sel-- } }                       # Up
                    40 { if ($sel -lt $list.Count - 1) { $sel++ } }          # Down
                    { $_ -in 13,39 } { if ($list.Count -gt 0) { $mode = 'detail' } } # Enter / Right
                    default {
                        switch ($ch) {
                            'q' { break outer }
                            'n' {
                                [Console]::CursorVisible = $true
                                Clear-Host
                                $nm = Read-Host "  New snippet name"
                                $la = Read-Host "  Language [$( (script:LoadCfg).DefaultLanguage )]"
                                $de = Read-Host "  Description (optional)"
                                [Console]::CursorVisible = $false
                                if ($nm) {
                                    if (-not $la) { $la = (script:LoadCfg).DefaultLanguage }
                                    New-Snip -Name $nm -Language $la -Description $de
                                    $idx = script:LoadIdx
                                    $msg = "[+] Created '$nm'"
                                }
                                Clear-Host
                            }
                            'e' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    Clear-Host; Edit-Snip -Name $list[$sel].Name
                                    $idx = script:LoadIdx
                                    $msg = "[+] Saved changes to '$($list[$sel].Name)'"
                                    [Console]::CursorVisible = $false; Clear-Host
                                }
                            }
                            'r' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    Clear-Host; Invoke-Snip -Name $list[$sel].Name
                                    Read-Host "`n  [Press Enter to return]"
                                    [Console]::CursorVisible = $false; Clear-Host
                                }
                            }
                            'c' {
                                if ($list.Count -gt 0) { Copy-Snip -Name $list[$sel].Name; $msg = "[+] Copied to clipboard" }
                            }
                            'd' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    $yn = Read-Host "  Delete '$($list[$sel].Name)'? [y/N]"
                                    [Console]::CursorVisible = $false
                                    if ($yn -in 'y','Y') {
                                        Remove-Snip -Name $list[$sel].Name -Force
                                        $idx = script:LoadIdx
                                        if ($sel -ge $list.Count - 1 -and $sel -gt 0) { $sel-- }
                                        $msg = "[+] Deleted"
                                    }
                                    Clear-Host
                                }
                            }
                            'g' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    Clear-Host; Export-Gist -Name $list[$sel].Name
                                    $idx = script:LoadIdx
                                    Read-Host "`n  [Press Enter to return]"
                                    [Console]::CursorVisible = $false; Clear-Host
                                }
                            }
                            '/' {
                                [Console]::CursorVisible = $true
                                $query = Read-Host "  Search"
                                [Console]::CursorVisible = $false
                                $sel = 0; Clear-Host
                            }
                        }
                    }
                }
            } else {
                # detail mode
                switch ($vk) {
                    { $_ -in 27,37 } { $mode = 'list'; Clear-Host }   # Esc / Left
                    default {
                        switch ($ch) {
                            'e' {
                                [Console]::CursorVisible = $true
                                Clear-Host; Edit-Snip -Name $list[$sel].Name
                                $idx = script:LoadIdx
                                [Console]::CursorVisible = $false; Clear-Host
                            }
                            'r' {
                                [Console]::CursorVisible = $true
                                Clear-Host; Invoke-Snip -Name $list[$sel].Name
                                Read-Host "`n  [Press Enter to return]"
                                [Console]::CursorVisible = $false; Clear-Host
                            }
                            'c' { Copy-Snip -Name $list[$sel].Name }
                            'g' {
                                [Console]::CursorVisible = $true
                                Clear-Host; Export-Gist -Name $list[$sel].Name
                                $idx = script:LoadIdx
                                Read-Host "`n  [Press Enter to return]"
                                [Console]::CursorVisible = $false; Clear-Host
                            }
                        }
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        Clear-Host
    }
}

#endregion

#region ─── snip dispatcher ──────────────────────────────────────────────────
# The 'snip' function is the primary CLI entry point. It routes sub-commands
# using a regex switch, mapping short aliases (ls, rm, cp, etc.) to the full
# public functions above. Named switches (-Language, -Tags, etc.) are forwarded
# to the appropriate function.

function Invoke-SnipCLI {
    <#
    .SYNOPSIS
        PSSnips main entry point (Invoke-SnipCLI, alias: snip) — dispatches sub-commands or launches the interactive TUI.

    .DESCRIPTION
        Invoke-SnipCLI (invoked via the 'snip' alias) is the primary command-line interface
        for PSSnips. When called with no arguments it launches the full-screen interactive TUI.
        With a sub-command it routes to the appropriate PSSnips function.

        Sub-commands:
          (none) / ui / tui  Open the interactive TUI (Start-SnipManager)
          list  [filter]     List snippets (Get-Snip)
          new   <name>       Create a snippet and open in editor (New-Snip)
          add   <name>       Add from -Path file or pipe (Add-Snip)
          show  <name>       Display snippet content (Show-Snip)
          edit  <name>       Open snippet in editor (Edit-Snip)
          run   <name>       Execute snippet (Invoke-Snip)
          rm    <name>       Delete snippet (Remove-Snip)
          copy  <name>       Copy to clipboard (Copy-Snip)
          tag   <name>       Manage tags (Set-SnipTag)
          search <query>     Search by name/description/tag (Get-Snip -Filter)
          config             View or update configuration (Get/Set-SnipConfig)
          gist list          List GitHub Gists (Get-GistList)
          gist show  <id>    Display a Gist (Get-Gist)
          gist import <id>   Import a Gist locally (Import-Gist)
          gist push  <name>  Export snippet to GitHub Gist (Export-Gist)
          gist run   <id>    Run a Gist without saving (Invoke-Gist)
          gist sync  <name>  Sync snippet with its Gist (Sync-Gist)
          help               Display this help

    .PARAMETER Command
        The sub-command to execute. Omit to launch the interactive TUI.
        Accepts short aliases: ls, n, a, s, e, r, rm/del, cp/yank, f.

    .PARAMETER Arg1
        First positional argument for the sub-command, typically the snippet name
        or the Gist sub-command (list, show, import, push, run, sync).

    .PARAMETER Arg2
        Second positional argument, typically a Gist ID or file name.

    .PARAMETER Language
        Language/extension override (ps1, py, js, bat, sh, rb, go, ...).
        Forwarded to New-Snip, Add-Snip, or Set-SnipConfig as appropriate.

    .PARAMETER Description
        Short description for new or exported snippets.

    .PARAMETER Tags
        Array of tag strings for new snippets or tag operations.

    .PARAMETER Content
        Snippet content string forwarded to New-Snip (bypasses editor).

    .PARAMETER Path
        Source file path forwarded to Add-Snip -Path.

    .PARAMETER Editor
        Editor command override forwarded to New-Snip or Edit-Snip.

    .PARAMETER Token
        GitHub personal access token forwarded to Set-SnipConfig -GitHubToken.

    .PARAMETER Username
        GitHub username forwarded to Set-SnipConfig -GitHubUsername.

    .PARAMETER Public
        Creates a public GitHub Gist (forwarded to Export-Gist).

    .PARAMETER Force
        Skips confirmation prompts (forwarded to Remove-Snip or Add-Snip).

    .PARAMETER Push
        With 'gist sync': pushes local content to GitHub instead of pulling.

    .PARAMETER Clip
        With 'add': reads content from the Windows clipboard.

    .PARAMETER All
        With 'gist import': imports all files from the Gist.

    .EXAMPLE
        snip

        Launches the interactive full-screen TUI snippet manager.

    .EXAMPLE
        snip new deploy -Language ps1 -Description 'Deploy to Azure'

        Creates a new PowerShell snippet named 'deploy' and opens the editor.

    .EXAMPLE
        snip add loader -Path .\loader.py

        Imports loader.py from disk as a snippet named 'loader'.

    .EXAMPLE
        snip gist import abc123def456abc123def456abc1234567 -Name handy-script

        Downloads a GitHub Gist and saves it as local snippet 'handy-script'.

    .EXAMPLE
        snip config -Token ghp_abc123

        Saves a GitHub PAT to the configuration for Gist operations.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Variable. Depends on the sub-command. Most commands write to the host;
        list and search commands also return PSCustomObject arrays.

    .NOTES
        Calling 'snip <name>' where <name> matches an existing snippet calls
        Show-Snip directly, making snippet names first-class sub-commands.
        Short aliases are resolved via regex matching in the internal switch statement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]   $Command     = '',
        [Parameter(Position=1)][string]   $Arg1        = '',
        [Parameter(Position=2)][string]   $Arg2        = '',
        [Parameter(ValueFromRemainingArguments)][string[]]$Rest = @(),
        [string]  $Language    = '',
        [string]  $Description = '',
        [string[]]$Tags        = @(),
        [string]  $Content     = '',
        [string]  $Path        = '',
        [string]  $Editor      = '',
        [string]  $Token       = '',
        [string]  $Username    = '',
        [switch]  $Public,
        [switch]  $Force,
        [switch]  $Push,
        [switch]  $Clip,
        [switch]  $All,
        [switch]  $Shared,
        [switch]  $IgnoreDuplicate,
        [string]  $Visibility    = '',
        [string]  $Scope         = ''
    )

    switch -Regex ($Command.ToLower()) {

        '^(|ui|tui)$' { Start-SnipManager }

        '^(list|ls|l)$' {
            $f = if ($Arg1) { $Arg1 } else { '' }
            Get-Snip -Filter $f -Shared:$Shared | Out-Null
        }

        '^(show|cat|view|s)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip show <name>"; return }
            Show-Snip -Name $n
        }

        '^(new|create|n)$' {
            $n = if ($Arg1) { $Arg1 } else { Read-Host "  Snippet name" }
            $l = if ($Language) { $Language } elseif ($Arg2) { $Arg2 } else { '' }
            New-Snip -Name $n -Language $l -Description $Description -Tags $Tags -Content $Content -Editor $Editor -IgnoreDuplicate:$IgnoreDuplicate
        }

        '^(add|a)$' {
            $n = if ($Arg1) { $Arg1 } else { Read-Host "  Snippet name" }
            $p = if ($Path) { $Path } elseif ($Arg2) { $Arg2 } else { '' }
            if ($Clip) {
                Add-Snip -Name $n -FromClipboard -Language $Language -Description $Description -Tags $Tags -Force:$Force -IgnoreDuplicate:$IgnoreDuplicate
            } elseif ($p) {
                Add-Snip -Name $n -Path $p -Language $Language -Description $Description -Tags $Tags -Force:$Force -IgnoreDuplicate:$IgnoreDuplicate
            } else {
                script:Out-Err "Specify -Path <file> or -Clip for clipboard."
            }
        }

        '^(edit|e)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip edit <name>"; return }
            Edit-Snip -Name $n -Editor $Editor
        }

        '^(run|exec|r)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip run <name>"; return }
            Invoke-Snip -Name $n -ArgumentList $Rest
        }

        '^(remove|delete|rm|del)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip rm <name>"; return }
            Remove-Snip -Name $n -Force:$Force
        }

        '^(copy|cp|yank)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip copy <name>"; return }
            Copy-Snip -Name $n
        }

        '^tag$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip tag <name> -Tags t1,t2"; return }
            Set-SnipTag -Name $n -Tags $Tags -Add @() -Remove @()
        }

        '^(search|find|f)$' {
            $q = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip search <query>"; return }
            Get-Snip -Filter $q | Out-Null
        }

        '^config$' {
            if     ($Token)    { Set-SnipConfig -GitHubToken    $Token    }
            elseif ($Username) { Set-SnipConfig -GitHubUsername $Username }
            elseif ($Editor)   { Set-SnipConfig -Editor         $Editor   }
            elseif ($Language) { Set-SnipConfig -DefaultLanguage $Language }
            else               { Get-SnipConfig }
        }

        '^gist$' {
            $sub = $Arg1.ToLower()
            switch -Regex ($sub) {
                '^(list|ls|)$' {
                    $f = if ($Arg2) { $Arg2 } else { '' }
                    Get-GistList -Filter $f | Out-Null
                }
                '^(show|get|view)$' {
                    $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gist show <id>"; return }
                    Get-Gist -GistId $id
                }
                '^(import|pull|clone)$' {
                    $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gist import <id>"; return }
                    $n  = if ($Rest) { $Rest[0] } else { '' }
                    if ($n) { Import-Gist -GistId $id -Name $n -All:$All }
                    else    { Import-Gist -GistId $id           -All:$All }
                }
                '^(push|export)$' {
                    $n = $Arg2; if (-not $n) { script:Out-Err "Usage: snip gist push <name>"; return }
                    Export-Gist -Name $n -Description $Description -Public:$Public
                }
                '^(run|exec)$' {
                    $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gist run <id>"; return }
                    Invoke-Gist -GistId $id -ArgumentList $Rest
                }
                '^sync$' {
                    $n = $Arg2; if (-not $n) { script:Out-Err "Usage: snip gist sync <name>"; return }
                    Sync-Gist -Name $n -Push:$Push
                }
                default {
                    # bare gist id?
                    if ($Arg1 -match '^[a-f0-9]{20,}$') { Get-Gist -GistId $Arg1 }
                    else { Write-Host "`n  Gist sub-commands: list, show, import, push, run, sync`n" -ForegroundColor DarkCyan }
                }
            }
        }

        '^(pipeline|chain)$' {
            if (-not $Arg1) { script:Out-Err "Usage: snip pipeline <name1,name2,...>"; return }
            $names = ($Arg1 -split ',') + @($Rest | Where-Object { $_ })
            $names = @($names | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $ceFlag = $Force  # reuse -Force switch for -ContinueOnError in pipeline context
            Invoke-Snip -Pipeline $names -ContinueOnError:$ceFlag
        }

        '^gitlab$' {
            $sub = $Arg1.ToLower()
            switch -Regex ($sub) {
                '^(list|ls|)$'    { Get-GitLabSnipList -Filter (if ($Arg2) { $Arg2 } else { '' }) | Out-Null }
                '^(get|show)$'    { $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gitlab get <id>"; return }; Get-GitLabSnip -SnipId $id }
                '^(import|pull)$' { $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gitlab import <id>"; return }; Import-GitLabSnip -SnipId $id -Force:$Force }
                '^(export|push)$' { $n = $Arg2; if (-not $n) { script:Out-Err "Usage: snip gitlab export <name>"; return }; $v = if ($Visibility) { $Visibility } else { 'private' }; Export-GitLabSnip -Name $n -Description $Description -Visibility $v }
                default           { Write-Host "`n  GitLab sub-commands: list, get, import, export`n" -ForegroundColor DarkCyan }
            }
        }

        '^gitlab-list$'   { Get-GitLabSnipList -Filter (if ($Arg1) { $Arg1 } else { '' }) | Out-Null }
        '^gitlab-get$'    { $id = $Arg1; if (-not $id) { script:Out-Err "Usage: snip gitlab-get <id>"; return }; Get-GitLabSnip -SnipId $id }
        '^gitlab-import$' { $id = $Arg1; if (-not $id) { script:Out-Err "Usage: snip gitlab-import <id>"; return }; Import-GitLabSnip -SnipId $id -Force:$Force }
        '^gitlab-export$' { $n = $Arg1; if (-not $n) { script:Out-Err "Usage: snip gitlab-export <name>"; return }; $v = if ($Visibility) { $Visibility } else { 'private' }; Export-GitLabSnip -Name $n -Description $Description -Visibility $v }

        '^publish$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip publish <name>"; return }
            Publish-Snip -Name $n -Force:$Force
        }

        '^sync-shared$' { Sync-SharedSnips -Force:$Force }

        '^install$'   { $s = if ($Scope) { $Scope } else { 'CurrentUserCurrentHost' }; Install-PSSnips -Scope $s -Force:$Force }
        '^uninstall$' { $s = if ($Scope) { $Scope } else { 'CurrentUserCurrentHost' }; Uninstall-PSSnips -Scope $s }

        '^(help|h|\?)$' {
            script:Out-Banner
            Get-Help snip -Full
        }

        default {
            # If command matches a known snippet name, show it
            $idx = script:LoadIdx
            if ($idx.snippets.ContainsKey($Command)) { Show-Snip -Name $Command }
            else { script:Out-Err "Unknown command '$Command'. Run 'snip help' for usage." }
        }
    }
}
Set-Alias -Name snip -Value Invoke-SnipCLI -Scope Global -Description 'PSSnips dispatcher alias'

#endregion

#region ─── Argument Completers ──────────────────────────────────────────────
# Tab-completion for snippet names on all relevant commands.

$snipNameCompleter = {
    param($cmd, $param, $word)
    $null = $cmd, $param
    $now = Get-Date
    if ($null -eq $script:CompleterCache -or
        ($now - $script:CompleterCacheTime).TotalSeconds -gt $script:CompleterTtlSecs) {
        $script:CompleterCache = (script:LoadIdx).snippets.Keys | Sort-Object
        $script:CompleterCacheTime = $now
    }
    $script:CompleterCache | Where-Object { $_ -like "$word*" }
}

Register-ArgumentCompleter -CommandName 'Invoke-SnipCLI','snip','Show-Snip','Edit-Snip','Invoke-Snip','Remove-Snip','Copy-Snip','Export-Gist','Sync-Gist','Set-SnipTag' -ParameterName Name -ScriptBlock $snipNameCompleter
Register-ArgumentCompleter -CommandName 'Invoke-SnipCLI','snip' -ParameterName Arg1 -ScriptBlock $snipNameCompleter

#endregion

#region ─── Auto-init ────────────────────────────────────────────────────────
# Initialize-PSSnips is the public-facing init function.
# script:InitEnv is called automatically at module load (bottom of this region).

function Initialize-PSSnips {
    <#
    .SYNOPSIS
        Initializes the PSSnips data directory and writes the default configuration.

    .DESCRIPTION
        Creates the ~/.pssnips directory and its snippets subdirectory if they do not
        exist. Writes a default config.json and an empty index.json when those files
        are absent. Displays the detected editor and reminds the user to configure a
        GitHub token if Gist features are needed. This function is called automatically
        when the module is imported; calling it manually is useful after a fresh
        installation or to repair a missing configuration.

    .EXAMPLE
        Initialize-PSSnips

        Ensures the data directory and config files exist and reports the ready state.

    .EXAMPLE
        # Re-initialise after manually deleting the config directory
        Remove-Item ~/.pssnips -Recurse -Force
        Initialize-PSSnips

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes status messages to the host.

    .NOTES
        The module calls script:InitEnv automatically on import, so explicit calls to
        Initialize-PSSnips are typically not needed in normal usage.
        Data directory: ~/.pssnips  (controlled by $script:Home)
    #>
    [CmdletBinding()]
    param()
    script:InitEnv
    script:Out-OK "PSSnips ready at: $script:Home"
    script:Out-Info "Editor: $(script:GetEditor)"
    script:Out-Info "Run 'snip config -GitHubToken <token>' to enable GitHub Gist features."
}

# Initialize on module load
script:InitEnv

#endregion

#region ─── Analytics & Utilities ────────────────────────────────────────────
# Get-StaleSnip, Get-SnipStats, Export-VSCodeSnips, Invoke-FuzzySnip

function Get-StaleSnip {
    <#
    .SYNOPSIS
        Lists snippets that have not been run in N days (or have never been run).

    .DESCRIPTION
        Reads the snippet index and identifies snippets whose last execution date
        falls at or beyond the specified staleness threshold. Optionally includes
        snippets that have no recorded execution at all. Results are sorted with
        the most idle snippets first. Use -PassThru to receive the objects
        directly for further pipeline processing instead of displaying the table.

    .PARAMETER DaysUnused
        The staleness threshold in days. Snippets whose last run was at least this
        many days ago are included. Defaults to 90.

    .PARAMETER IncludeNeverRun
        When specified, snippets with no recorded run (runCount is absent or zero)
        are also included in the results. They are shown with DaysIdle = MaxValue
        and sorted to the bottom of the list (after legitimately stale snippets).

    .PARAMETER PassThru
        When specified, suppresses the formatted table output and returns the
        result objects directly so they can be piped to further commands.

    .EXAMPLE
        Get-StaleSnip

        Lists all snippets that have not been run in 90 or more days.

    .EXAMPLE
        Get-StaleSnip -DaysUnused 30 -IncludeNeverRun

        Lists snippets idle for 30+ days plus any that have never been run.

    .EXAMPLE
        Get-StaleSnip -DaysUnused 60 -PassThru | Remove-Snip

        Retrieves stale snippet objects and pipes their names to Remove-Snip.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: Name, Language, Tags, LastRun, DaysIdle, RunCount.

    .NOTES
        DaysIdle is computed from [datetime]::Now. Snippets with no lastRun entry
        and -IncludeNeverRun will show DaysIdle as 2147483647 ([int]::MaxValue).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateRange(0, [int]::MaxValue)]
        [int]$DaysUnused = 90,
        [switch]$IncludeNeverRun,
        [switch]$PassThru
    )
    script:InitEnv
    $idx = script:LoadIdx

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($name in $idx.snippets.Keys) {
        $entry    = $idx.snippets[$name]
        $hasRun   = $entry.ContainsKey('lastRun') -and $entry['lastRun']
        $runCount = if ($entry.ContainsKey('runCount')) { [int]$entry['runCount'] } else { 0 }

        if ($hasRun) {
            $daysIdle = ([datetime]::Now - [datetime]$entry['lastRun']).Days
        } elseif ($IncludeNeverRun) {
            $daysIdle = [int]::MaxValue
        } else {
            continue
        }

        if ($daysIdle -ge $DaysUnused) {
            $results.Add([pscustomobject]@{
                Name     = $name
                Language = $entry['language']
                Tags     = @($entry['tags']) -join ', '
                LastRun  = if ($hasRun) { [datetime]$entry['lastRun'] | Get-Date -Format 'yyyy-MM-dd' } else { 'Never' }
                DaysIdle = if ($daysIdle -eq [int]::MaxValue) { '∞' } else { $daysIdle }
                RunCount = $runCount
            })
        }
    }

    # Sort: finite DaysIdle descending, then never-run entries last
    $sorted = @($results | Sort-Object {
        if ($_.DaysIdle -eq '∞') { [int]::MaxValue } else { [int]$_.DaysIdle }
    } -Descending)

    if (-not $PassThru) {
        if ($sorted.Count -eq 0) {
            script:Out-Info "No stale snippets found (threshold: $DaysUnused days)."
        } else {
            Write-Host ""
            Write-Host "  Stale Snippets  (idle ≥ $DaysUnused days)" -ForegroundColor Cyan
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            Write-Host ("  {0,-23} {1,-5} {2,-10} {3,-8} {4}" -f 'NAME','LANG','LAST RUN','DAYS IDLE','TAGS') -ForegroundColor DarkCyan
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            foreach ($r in $sorted) {
                $c = script:LangColor -ext $r.Language
                Write-Host ("  {0,-23} " -f $r.Name) -ForegroundColor $c -NoNewline
                Write-Host ("{0,-5} {1,-10} {2,-8} {3}" -f $r.Language, $r.LastRun, $r.DaysIdle, $r.Tags) -ForegroundColor Gray
            }
            Write-Host ""
        }
    }

    return $sorted
}

function Get-SnipStats {
    <#
    .SYNOPSIS
        Shows execution analytics — run counts, last run times, and usage leaderboard.

    .DESCRIPTION
        Reads the snippet index and builds a ranked leaderboard of the most frequently
        or most recently run snippets. Snippets that have never been run are included
        with a RunCount of 0. Use -All to see the full collection rather than just
        the top N entries. Use -PassThru to receive the ranked objects for pipeline
        processing without printing the table.

    .PARAMETER Top
        The number of top entries to display. Defaults to 10. Ignored when -All is set.

    .PARAMETER SortBy
        The field used to rank and sort results. Valid values:
          RunCount  – most-run snippets first (default)
          LastRun   – most-recently run snippets first
          Name      – alphabetical ascending

    .PARAMETER All
        When specified, all snippets are included regardless of -Top.

    .PARAMETER PassThru
        When specified, suppresses the formatted table and returns the ranked
        objects directly for pipeline use.

    .EXAMPLE
        Get-SnipStats

        Displays the top 10 snippets by run count.

    .EXAMPLE
        Get-SnipStats -Top 20 -SortBy LastRun

        Displays the 20 most-recently run snippets.

    .EXAMPLE
        Get-SnipStats -All -PassThru | Export-Csv stats.csv -NoTypeInformation

        Returns all snippet stat objects and exports them to CSV.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: Rank, Name, Language, RunCount, LastRun, Tags.

    .NOTES
        Snippets with no runCount entry are treated as RunCount = 0.
        Snippets with no lastRun entry are shown as LastRun = 'Never'.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Top = 10,
        [ValidateSet('RunCount','LastRun','Name')]
        [string]$SortBy = 'RunCount',
        [switch]$All,
        [switch]$PassThru
    )
    script:InitEnv
    $idx = script:LoadIdx

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($name in $idx.snippets.Keys) {
        $entry    = $idx.snippets[$name]
        $runCount = if ($entry.ContainsKey('runCount')) { [int]$entry['runCount'] } else { 0 }
        $lastRun  = if ($entry.ContainsKey('lastRun') -and $entry['lastRun']) {
            [datetime]$entry['lastRun'] | Get-Date -Format 'yyyy-MM-dd HH:mm'
        } else { 'Never' }
        $rows.Add([pscustomobject]@{
            Rank     = 0   # assigned after sort
            Name     = $name
            Language = $entry['language']
            RunCount = $runCount
            LastRun  = $lastRun
            Tags     = @($entry['tags']) -join ', '
        })
    }

    $sorted = switch ($SortBy) {
        'RunCount' { @($rows | Sort-Object RunCount -Descending) }
        'LastRun'  {
            # 'Never' entries sort to bottom
            @($rows | Sort-Object {
                if ($_.LastRun -eq 'Never') { [datetime]::MinValue } else { [datetime]$_.LastRun }
            } -Descending)
        }
        'Name'     { @($rows | Sort-Object Name) }
        default    { @($rows | Sort-Object RunCount -Descending) }
    }

    if (-not $All) { $sorted = @($sorted | Select-Object -First $Top) }

    # Assign 1-based rank
    for ($i = 0; $i -lt $sorted.Count; $i++) { $sorted[$i].Rank = $i + 1 }

    if (-not $PassThru) {
        if ($sorted.Count -eq 0) {
            script:Out-Info "No snippets found."
        } else {
            $neverRun = @($sorted | Where-Object { $_.RunCount -eq 0 }).Count
            Write-Host ""
            Write-Host "  Snippet Execution Statistics" -ForegroundColor Cyan
            $subtitle = if ($All) { "All $($sorted.Count) snippets" } else { "Top $($sorted.Count)" }
            Write-Host "  $subtitle · sorted by $SortBy" -ForegroundColor DarkGray
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            Write-Host ("  {0,4}  {1,-23} {2,-5} {3,8}  {4,-17} {5}" -f '#','NAME','LANG','RUNS','LAST RUN','TAGS') -ForegroundColor DarkCyan
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            foreach ($r in $sorted) {
                $c        = script:LangColor -ext $r.Language
                $runsDisp = if ($r.RunCount -gt 0) { "$($r.RunCount)" } else { '—' }
                Write-Host ("  {0,4}  {1,-23} " -f $r.Rank, $r.Name) -ForegroundColor $c -NoNewline
                Write-Host ("{0,-5} {1,8}  {2,-17} {3}" -f $r.Language, $runsDisp, $r.LastRun, $r.Tags) -ForegroundColor Gray
            }
            Write-Host ""
            if ($neverRun -eq $sorted.Count) {
                script:Out-Info "No snippets have been run yet. Use 'snip run <name>' to execute one."
            }
        }
    }

    return $sorted
}

function Export-VSCodeSnips {
    <#
    .SYNOPSIS
        Exports the PSSnips collection to VS Code user snippets format.

    .DESCRIPTION
        Reads local snippets and writes them as VS Code user snippet JSON files
        (one file per language) to the VS Code User snippets directory. Each snippet
        is written in the standard VS Code format with prefix, body array, and
        description fields. Use -Language to export only one language. Use -WhatIf
        to preview what would be written without touching any files. Use -PassThru
        to receive the generated JSON hashtable objects for further processing.

        Auto-detected VS Code snippets directory locations (in preference order):
          %APPDATA%\Code\User\snippets          (VS Code Stable)
          %APPDATA%\Code - Insiders\User\snippets  (VS Code Insiders)

        Language-to-filename mapping:
          ps1/psm1 → powershell.json    py  → python.json
          js       → javascript.json    ts  → typescript.json
          sh/bash  → shellscript.json   rb  → ruby.json
          go       → go.json            sql → sql.json
          md       → markdown.json      txt/other → plaintext.json

    .PARAMETER Language
        Optional. Filter to a single language extension (e.g., 'ps1', 'py', 'js').
        When omitted all languages present in the index are exported.

    .PARAMETER OutputDir
        Optional. Path to the VS Code snippets directory. When omitted the
        auto-detected path is used. The directory must already exist.

    .PARAMETER WhatIf
        When specified, prints "Would write <path>" for each file that would be
        written without actually writing anything.

    .PARAMETER PassThru
        When specified, returns the generated snippet hashtables keyed by output
        file path instead of (or in addition to) writing them.

    .EXAMPLE
        Export-VSCodeSnips

        Exports all snippets to the auto-detected VS Code snippets directory.

    .EXAMPLE
        Export-VSCodeSnips -Language ps1 -WhatIf

        Previews what would be written for PowerShell snippets only.

    .EXAMPLE
        Export-VSCodeSnips -OutputDir 'C:\MySnippets'

        Exports all snippets to a custom directory.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable (keyed by output path) when -PassThru is set.
        Otherwise None — writes files and prints confirmation messages.

    .NOTES
        Snippet file content is split on newlines to produce the VS Code body array.
        If the VS Code snippets directory cannot be detected and -OutputDir is not
        provided, the function warns and exits without writing any files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [string]$Language  = '',
        [string]$OutputDir = '',
        [switch]$WhatIf,
        [switch]$PassThru
    )
    script:InitEnv

    # ── Resolve output directory ────────────────────────────────────────────
    $resolvedDir = $OutputDir
    if (-not $resolvedDir) {
        $candidates = @(
            (Join-Path $env:APPDATA 'Code\User\snippets'),
            (Join-Path $env:APPDATA 'Code - Insiders\User\snippets')
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $resolvedDir = $c; break }
        }
    }
    if (-not $resolvedDir -or -not (Test-Path $resolvedDir)) {
        script:Out-Warn "VS Code snippets directory not found. Provide -OutputDir or install VS Code."
        return
    }

    # ── Language → VS Code filename map ────────────────────────────────────
    $langMap = @{
        ps1  = 'powershell.json';  psm1 = 'powershell.json'
        py   = 'python.json'
        js   = 'javascript.json'
        ts   = 'typescript.json'
        sh   = 'shellscript.json'; bash = 'shellscript.json'
        rb   = 'ruby.json'
        go   = 'go.json'
        sql  = 'sql.json'
        md   = 'markdown.json'
    }

    $idx = script:LoadIdx
    $cfg = script:LoadCfg

    # ── Group snippets by VS Code output file ──────────────────────────────
    $byFile = @{}   # outPath → hashtable of VS Code snippet entries
    foreach ($name in $idx.snippets.Keys) {
        $entry = $idx.snippets[$name]
        $lang  = $entry['language']
        if ($Language -and $lang -ne $Language) { continue }

        $vsFile = if ($langMap.ContainsKey($lang)) { $langMap[$lang] } else { 'plaintext.json' }
        $outPath = Join-Path $resolvedDir $vsFile

        $snipPath = script:FindFile -Name $name
        if (-not $snipPath -or -not (Test-Path $snipPath)) { continue }

        $bodyLines = @(Get-Content $snipPath -Encoding UTF8)
        $desc = if ($entry.ContainsKey('description') -and $entry['description']) { $entry['description'] } else { $name }

        if (-not $byFile.ContainsKey($outPath)) { $byFile[$outPath] = @{} }
        $byFile[$outPath][$name] = @{
            prefix      = $name
            body        = $bodyLines
            description = $desc
        }
    }

    if ($byFile.Count -eq 0) {
        script:Out-Info "No snippets to export$(if ($Language) { " for language '$Language'" })."
        return
    }

    $passThruResult = @{}

    foreach ($outPath in ($byFile.Keys | Sort-Object)) {
        $fileSnips = $byFile[$outPath]

        # Merge with existing VS Code snippets file when present
        $merged = @{}
        if (Test-Path $outPath) {
            try {
                $existing = Get-Content $outPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -AsHashtable
                foreach ($k in $existing.Keys) { $merged[$k] = $existing[$k] }
            } catch { Write-Verbose "Export-VSCodeSnips: could not read existing file '$outPath' — overwriting." }
        }
        foreach ($k in $fileSnips.Keys) { $merged[$k] = $fileSnips[$k] }

        if ($WhatIf -or $PSCmdlet.ShouldProcess($outPath, 'Write VS Code snippets file')) {
            if ($WhatIf) {
                script:Out-Info "Would write $($fileSnips.Count) snippet(s) → $outPath"
            } else {
                $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding UTF8
                script:Out-OK "Wrote $($fileSnips.Count) snippet(s) → $outPath"
            }
        }

        if ($PassThru) { $passThruResult[$outPath] = $merged }
    }

    if ($PassThru) { return $passThruResult }
}

function Invoke-FuzzySnip {
    <#
    .SYNOPSIS
        Launches an interactive fuzzy-finder picker for snippets using fzf.

    .DESCRIPTION
        Pipes all snippet names to fzf (or PSFzf's Invoke-Fzf) for interactive
        fuzzy selection, then executes the chosen action — Show, Run, or Edit — on
        the selected snippet. Requires fzf on PATH or the PSFzf module installed.
        When neither is available, falls back to Get-Snip to list snippets with a
        warning explaining how to install fzf.

    .PARAMETER Action
        The action to execute on the selected snippet:
          Show  – display the snippet content (default)
          Run   – execute the snippet via Invoke-Snip
          Edit  – open the snippet in the configured editor via Edit-Snip

    .PARAMETER Filter
        Optional pre-filter string passed to fzf via --query so the picker opens
        with the search box already populated.

    .EXAMPLE
        Invoke-FuzzySnip

        Opens the fuzzy picker; pressing Enter on a selection shows it.

    .EXAMPLE
        Invoke-FuzzySnip -Action Run

        Opens the fuzzy picker and runs the selected snippet.

    .EXAMPLE
        Invoke-FuzzySnip -Action Edit -Filter azure

        Opens the fuzzy picker pre-filtered to 'azure' and edits the selection.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String
        The name of the selected snippet, or nothing if the user pressed Esc.

    .NOTES
        Install fzf:      winget install fzf
        Install PSFzf:    Install-Module PSFzf
        If only PSFzf is available (without the raw fzf binary on PATH), Invoke-Fzf
        from that module is used instead of piping to fzf directly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('Show','Run','Edit')]
        [string]$Action = 'Show',
        [string]$Filter = ''
    )
    script:InitEnv
    $idx = script:LoadIdx

    if ($idx.snippets.Count -eq 0) {
        script:Out-Info "No snippets yet. Use 'snip new <name>' to create one."
        return
    }

    $names = @($idx.snippets.Keys | Sort-Object)

    $fzfAvailable  = [bool](Get-Command fzf -ErrorAction SilentlyContinue)
    $psFzfAvailable = [bool](Get-Module -ListAvailable PSFzf -ErrorAction SilentlyContinue)

    if (-not $fzfAvailable -and -not $psFzfAvailable) {
        Write-Warning "fzf not found. Install via: winget install fzf  or: Install-Module PSFzf"
        Get-Snip
        return
    }

    $selected = $null

    if ($fzfAvailable) {
        $modulePath = $PSScriptRoot
        $previewCmd = "pwsh -NoProfile -Command `"Import-Module '$modulePath\PSSnips.psm1' -Force; Show-Snip -Name '{}'`""
        $fzfArgs    = @('--height','40%','--reverse','--preview',$previewCmd)
        if ($Filter) { $fzfArgs += @('--query', $Filter) }
        $selected = $names | & fzf @fzfArgs
    } elseif ($psFzfAvailable) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        $fzfParams = @{ Input = $names }
        if ($Filter) { $fzfParams['Query'] = $Filter }
        $selected = Invoke-Fzf @fzfParams
    }

    if (-not $selected) { return }   # user pressed Esc or made no selection

    switch ($Action) {
        'Show' { Show-Snip  -Name $selected }
        'Run'  { Invoke-Snip -Name $selected }
        'Edit' { Edit-Snip   -Name $selected }
    }

    return $selected
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-PSSnips',
    'Get-SnipConfig', 'Set-SnipConfig',
    'Get-Snip', 'Show-Snip', 'New-Snip', 'Add-Snip', 'Remove-Snip', 'Edit-Snip', 'Invoke-Snip', 'Copy-Snip', 'Set-SnipTag',
    'Export-SnipCollection', 'Import-SnipCollection',
    'Get-GistList', 'Get-Gist', 'Import-Gist', 'Export-Gist', 'Invoke-Gist', 'Sync-Gist',
    'Get-GitLabSnipList', 'Get-GitLabSnip', 'Import-GitLabSnip', 'Export-GitLabSnip',
    'Publish-Snip', 'Sync-SharedSnips',
    'Install-PSSnips', 'Uninstall-PSSnips',
    'Start-SnipManager',
    'Get-SnipHistory', 'Restore-Snip', 'Test-Snip',
    'Invoke-SnipCLI',
    'Get-StaleSnip', 'Get-SnipStats', 'Export-VSCodeSnips', 'Invoke-FuzzySnip'
) -Alias 'snip'
