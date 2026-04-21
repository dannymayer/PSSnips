# PSSnips — Backup and restore operations.
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
        foreach ($k in @($backupIdx.snippets.Keys)) {
            if ($backupIdx.snippets[$k] -is [hashtable]) {
                $backupIdx.snippets[$k] = [SnippetMetadata]::FromHashtable($backupIdx.snippets[$k])
            }
        }

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

                $lang    = $backupIdx.snippets[$snipName].Language
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

