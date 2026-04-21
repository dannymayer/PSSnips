#Requires -Version 7.0
<#
.SYNOPSIS
    Splits PSSnips.psm1 into Private/ and Public/ files (v3.0 Item 1).
    MECHANICAL EXTRACTION — no logic changes.
#>

$root  = 'C:\Users\DMayer\LaSalle St. Securities\Home Office - Platform Technology - Documents\Developer\Scripts\PSSnips'
$src   = Join-Path $root 'PSSnips.psm1'
$lines = Get-Content $src   # array of strings, 0-based

Write-Host "Source file: $src"
Write-Host "Total lines: $($lines.Count)"

# ── Helpers ────────────────────────────────────────────────────────────────────

# Extract a contiguous 1-based range [from..to]
function Get-L { param([int]$From, [int]$To) $lines[($From-1)..($To-1)] }

# Write an extracted file; first element of $Parts is the header comment
function Write-PSFile {
    param([string]$RelPath, [object[]]$Parts)
    $full = Join-Path $root $RelPath
    # Flatten parts (each part may itself be an array)
    $content = foreach ($p in $Parts) { $p }
    Set-Content -Path $full -Value $content -Encoding UTF8
    Write-Host "  Wrote $RelPath  ($(@($content).Count) lines)"
}

# ── Create directories ─────────────────────────────────────────────────────────
Write-Host "`nCreating directories..."
New-Item -ItemType Directory -Path (Join-Path $root 'Private')           -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'Public')            -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $root 'Private\Providers') -Force | Out-Null
Write-Host "  Private\, Public\, Private\Providers\ created."

# ── Extract Private files ──────────────────────────────────────────────────────
Write-Host "`nExtracting Private files..."

# Private\Data.ps1 — Module-Scoped Data (lines 23-102; skip #region @22 and #endregion @103)
Write-PSFile 'Private\Data.ps1' @(
    '# PSSnips — Module-scoped variables: paths, defaults, colour map, and templates.'
    Get-L 23 102
)

# Private\Logging.ps1 — Out-Banner + Out-OK/Err/Warn/Info (109-127)
Write-PSFile 'Private\Logging.ps1' @(
    '# PSSnips — Console output helpers (banner and status indicators).'
    Get-L 109 127
)

# Private\Parsing.ps1 — ParseCBH (128-167)
Write-PSFile 'Private\Parsing.ps1' @(
    '# PSSnips — Comment-Based Help parser.'
    Get-L 128 167
)

# Private\EventDispatch.ps1 — Invoke-SnipEvent (168-185)
Write-PSFile 'Private\EventDispatch.ps1' @(
    '# PSSnips — Internal event dispatch helper.'
    Get-L 168 185
)

# Private\IO.ps1 — EnsureDirs (186-192) + FindFile (328-337) + GetEditor (338-349) + LangColor (350-356)
Write-PSFile 'Private\IO.ps1' @(
    '# PSSnips — File-system and editor helpers.'
    Get-L 186 192
    ''
    Get-L 328 356
)

# Private\DataStore.ps1 — LoadCfg+SaveCfg+LoadIdx+SaveIdx (193-327)
#                         + AcquireLock+ReleaseLock+WithIdxLock+InitEnv+InvalidateCache (443-534)
Write-PSFile 'Private\DataStore.ps1' @(
    '# PSSnips — Config/index persistence, file locking, and environment initialisation.'
    Get-L 193 327
    ''
    Get-L 443 534
)

# Private\Credentials.ps1 — GetGitHubToken + GetGitLabToken + GetBitbucketCreds (357-403)
Write-PSFile 'Private\Credentials.ps1' @(
    '# PSSnips — Credential retrieval helpers (GitHub, GitLab, Bitbucket).'
    Get-L 357 403
)

# Private\ApiClients.ps1 — CallGitHub + CallGitLab (404-442)
Write-PSFile 'Private\ApiClients.ps1' @(
    '# PSSnips — Low-level HTTP client wrappers for GitHub and GitLab APIs.'
    Get-L 404 442
)

# Private\Fts.ps1 — SearchSnipContent + LoadFts + UpdateFts + RemoveFts (535-580)
Write-PSFile 'Private\Fts.ps1' @(
    '# PSSnips — Full-text search index helpers.'
    Get-L 535 580
)

# Private\Audit.ps1 — Write-AuditLog + GetSharedDir (581-613)
Write-PSFile 'Private\Audit.ps1' @(
    '# PSSnips — Audit logging and shared-directory helpers.'
    Get-L 581 613
)

# Private\Helpers.ps1 — GetContentHash (614-620) + SaveVersion (734-751)
Write-PSFile 'Private\Helpers.ps1' @(
    '# PSSnips — Miscellaneous helpers: content hashing and version history.'
    Get-L 614 620
    ''
    Get-L 734 751
)

# Private\Highlighting.ps1 — ConvertTo-HighlightedPS (623-706) + Invoke-BatHighlight (707-733)
Write-PSFile 'Private\Highlighting.ps1' @(
    '# PSSnips — Syntax highlighting helpers (ANSI tokenizer and bat).'
    Get-L 623 733
)

# Private\Completers.ps1 — Argument completers (lines 4884-4900; skip #region @4883 and #endregion @4901)
Write-PSFile 'Private\Completers.ps1' @(
    '# PSSnips — Tab-completion registrations for snippet name parameters.'
    Get-L 4884 4900
)

# ── Extract Public files ───────────────────────────────────────────────────────
Write-Host "`nExtracting Public files..."

# Public\Config.ps1 — comment (754-755) + Get-SnipConfig + Set-SnipConfig (756-1041)
Write-PSFile 'Public\Config.ps1' @(
    '# PSSnips — Get-SnipConfig and Set-SnipConfig: read/write module settings.'
    Get-L 754 1041
)

# Public\Core.ps1 — Snippet CRUD (1045-2685; skip #region @1044 and #endregion @2686)
Write-PSFile 'Public\Core.ps1' @(
    '# PSSnips — Core snippet CRUD: Get-Snip, New-Snip, Remove-Snip, Edit-Snip, etc.'
    Get-L 1045 2685
)

# Public\Backup.ps1 — Backup and Restore (2689-2941; skip #region @2688 and #endregion @2942)
Write-PSFile 'Public\Backup.ps1' @(
    '# PSSnips — Backup and restore operations.'
    Get-L 2689 2941
)

# Public\GitHub.ps1 — GitHub Gist (2945-3473; skip #region @2944 and #endregion @3474)
Write-PSFile 'Public\GitHub.ps1' @(
    '# PSSnips — GitHub Gist integration.'
    Get-L 2945 3473
)

# Public\GitLab.ps1 — GitLab functions (3477-3709; skip #region @3476, Bitbucket starts @3710)
Write-PSFile 'Public\GitLab.ps1' @(
    '# PSSnips — GitLab Snippets integration.'
    Get-L 3477 3709
)

# Public\Bitbucket.ps1 — Bitbucket functions (3710-4062; skip #endregion @4063)
Write-PSFile 'Public\Bitbucket.ps1' @(
    '# PSSnips — Bitbucket Snippets integration.'
    Get-L 3710 4062
)

# Public\Sharing.ps1 — Shared Storage (4066-4210; skip #region @4065 and #endregion @4211)
Write-PSFile 'Public\Sharing.ps1' @(
    '# PSSnips — Shared snippet storage (Publish-Snip, Sync-SharedSnips).'
    Get-L 4066 4210
)

# Public\Profile.ps1 — Profile Integration (4214-4307; skip #region @4213 and #endregion @4308)
Write-PSFile 'Public\Profile.ps1' @(
    '# PSSnips — Shell profile integration (Install-PSSnips, Uninstall-PSSnips).'
    Get-L 4214 4307
)

# Public\TUI.ps1 — Interactive TUI (4311-4572; skip #region @4310 and #endregion @4573)
Write-PSFile 'Public\TUI.ps1' @(
    '# PSSnips — Interactive terminal UI (Start-SnipManager).'
    Get-L 4311 4572
)

# Public\Dispatcher.ps1 — snip dispatcher (4576-4880; skip #region @4575 and #endregion @4881)
Write-PSFile 'Public\Dispatcher.ps1' @(
    '# PSSnips — Invoke-SnipCLI dispatcher and snip alias.'
    Get-L 4576 4880
)

# Analytics region split (4954-7006):
#   Analytics.ps1  : 4955-5915 (Get-StaleSnip..Add-SnipComment) + 6210-6849 (New-SnipSchedule..Unregister-SnipEvent)
#   Templates.ps1  : 5916-6209 (New-SnipFromTemplate + Get-SnipTemplate)
#   Linting.ps1    : 6850-7005 (Invoke-SnipLint + Test-SnipLint)

Write-PSFile 'Public\Analytics.ps1' @(
    '# PSSnips — Analytics, statistics, scheduling, and event-registry functions.'
    Get-L 4955 5915
    ''
    Get-L 6210 6849
)

Write-PSFile 'Public\Templates.ps1' @(
    '# PSSnips — Snippet template management (New-SnipFromTemplate, Get-SnipTemplate).'
    Get-L 5916 6209
)

Write-PSFile 'Public\Linting.ps1' @(
    '# PSSnips — Snippet linting via PSScriptAnalyzer (Invoke-SnipLint, Test-SnipLint).'
    Get-L 6850 7005
)

# ── Build new thin-loader PSSnips.psm1 ────────────────────────────────────────
Write-Host "`nBuilding new PSSnips.psm1 (thin loader)..."

# Auto-init content: lines 4904-4951 (between #region @4903 and #endregion @4952)
$autoInitLines = Get-L 4904 4951

# Export-ModuleMember: lines 7008-7031
$exportLines = Get-L 7008 7031

$newPsm1 = @(
    '#Requires -Version 7.0'
    ''
    'Set-StrictMode -Version Latest'
    '# $ErrorActionPreference is intentionally NOT set at module scope to avoid bleeding'
    "# into the caller's session. Individual functions use -ErrorAction Stop/Continue as needed."
    ''
    '# Load private files in dependency order'
    "foreach (`$file in @("
    "    'Private\Data.ps1',"
    "    'Private\Logging.ps1',"
    "    'Private\Parsing.ps1',"
    "    'Private\EventDispatch.ps1',"
    "    'Private\IO.ps1',"
    "    'Private\DataStore.ps1',"
    "    'Private\Credentials.ps1',"
    "    'Private\ApiClients.ps1',"
    "    'Private\Fts.ps1',"
    "    'Private\Audit.ps1',"
    "    'Private\Helpers.ps1',"
    "    'Private\Highlighting.ps1'"
    ')) {'
    "    . (Join-Path `$PSScriptRoot `$file)"
    '}'
    ''
    '# Load public files'
    "foreach (`$file in @("
    "    'Public\Config.ps1',"
    "    'Public\Core.ps1',"
    "    'Public\Backup.ps1',"
    "    'Public\GitHub.ps1',"
    "    'Public\GitLab.ps1',"
    "    'Public\Bitbucket.ps1',"
    "    'Public\Sharing.ps1',"
    "    'Public\Profile.ps1',"
    "    'Public\TUI.ps1',"
    "    'Public\Dispatcher.ps1',"
    "    'Public\Analytics.ps1',"
    "    'Public\Templates.ps1',"
    "    'Public\Linting.ps1'"
    ')) {'
    "    . (Join-Path `$PSScriptRoot `$file)"
    '}'
    ''
    '# Argument completers'
    ". (Join-Path `$PSScriptRoot 'Private\Completers.ps1')"
    ''
    '#region ─── Auto-init ────────────────────────────────────────────────────────'
)
$newPsm1 += $autoInitLines
$newPsm1 += '#endregion'
$newPsm1 += ''
$newPsm1 += $exportLines

Set-Content -Path (Join-Path $root 'PSSnips.psm1') -Value $newPsm1 -Encoding UTF8
Write-Host "  Wrote PSSnips.psm1 ($($newPsm1.Count) lines)"

Write-Host "`nDone. Verifying file counts..."
$privateFiles = Get-ChildItem (Join-Path $root 'Private') -Filter '*.ps1' | Select-Object -ExpandProperty Name
$publicFiles  = Get-ChildItem (Join-Path $root 'Public')  -Filter '*.ps1' | Select-Object -ExpandProperty Name
Write-Host "  Private\: $($privateFiles -join ', ')"
Write-Host "  Public\:  $($publicFiles  -join ', ')"
