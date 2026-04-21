# PSSnips — Shared snippet storage (Publish-Snip, Sync-SharedSnips).

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

        $sharedIdx['snippets'][$Name] = if ($idx.snippets[$Name] -is [SnippetMetadata]) { $idx.snippets[$Name].ToHashtable() } else { $idx.snippets[$Name] }

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
        if ($meta -is [hashtable]) { $meta = [SnippetMetadata]::FromHashtable($meta) }
        $lang    = $meta.Language
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

