# PSSnips — Git repository sync for snippet store.
function Sync-SnipRepo {
    <#
    .SYNOPSIS
        Syncs the local snippet store directory with a remote git repository.

    .DESCRIPTION
        Sync-SnipRepo keeps a git-backed clone of the PSSnips snippet store in sync
        with a remote repository. It supports pull-only, push-only, bidirectional
        sync, and status-only modes.

        Configuration keys read via the PSSnips config system:
          SnipRepoUrl — remote repository URL
          SnipRepoDir — local clone path (default: <PSSnips home>/repo)

        If the local clone directory does not exist, the repository is cloned from
        the configured remote URL before any pull/push operations.

    .PARAMETER Remote
        Overrides the SnipRepoUrl config value for a single invocation. Use this
        for one-shot sync against a different remote without changing config.

    .PARAMETER Pull
        Pull remote changes into the local repository. Mutually exclusive with
        -Push and -Status.

    .PARAMETER Push
        Stage all local changes, commit with an auto-generated message, and push
        to the remote. Mutually exclusive with -Pull and -Status.

    .PARAMETER Status
        Show the output of `git status` without modifying the repository. When
        this switch is present, -Pull and -Push are ignored.

    .EXAMPLE
        Sync-SnipRepo

        Performs a bidirectional sync: pull remote changes then push local changes.

    .EXAMPLE
        Sync-SnipRepo -Remote 'https://github.com/user/snips.git' -Pull

        Pulls from the specified remote URL without changing the stored config.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        PSCustomObject with properties:
          Status  [string]  — 'Pulled', 'Pushed', 'Both', or 'StatusOnly'
          Branch  [string]  — current branch name
          Changes [int]     — number of changed files reported by git status --short

    .NOTES
        Requires git in PATH. Install from https://git-scm.com if missing.
        All git output is forwarded to the verbose stream.
        Write operations are gated by ShouldProcess (supports -WhatIf/-Confirm).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([PSCustomObject])]
    param(
        [string]$Remote = '',
        [switch]$Pull,
        [switch]$Push,
        [switch]$Status
    )

    # Verify git is available
    if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
        Write-Error 'git not found in PATH. Install Git from https://git-scm.com'
        return
    }

    $cfg     = script:LoadCfg
    $url     = if ($Remote) { $Remote } else { $cfg['SnipRepoUrl'] }
    $repoDir = if ($cfg['SnipRepoDir']) { $cfg['SnipRepoDir'] } else { Join-Path $script:Home 'repo' }

    # Clone if local directory does not exist
    if (-not (Test-Path $repoDir)) {
        if (-not $url) {
            script:Out-Err 'SnipRepoUrl is not configured. Set it with Set-SnipConfig or pass -Remote.'
            return
        }
        if ($PSCmdlet.ShouldProcess($repoDir, "Clone repository from $url")) {
            script:Out-Info "Cloning $url -> $repoDir"
            $cloneOut = & git clone $url $repoDir 2>&1
            $cloneOut | ForEach-Object { Write-Verbose $_ }
            if ($LASTEXITCODE -ne 0) {
                script:Out-Err "git clone failed (exit $LASTEXITCODE)"
                return
            }
        } else {
            return
        }
    }

    # Determine current branch
    $branchOut = & git -C $repoDir rev-parse --abbrev-ref HEAD 2>&1
    $branch    = if ($LASTEXITCODE -eq 0) { ($branchOut | Out-String).Trim() } else { 'unknown' }

    # Count changed files
    $shortOut = & git -C $repoDir status --short 2>&1
    $shortOut | ForEach-Object { Write-Verbose $_ }
    $changes  = @($shortOut | Where-Object { $_ -match '\S' }).Count

    # -Status: report only
    if ($Status) {
        $shortOut | ForEach-Object { script:Out-Info $_ }
        return [PSCustomObject]@{
            Status  = 'StatusOnly'
            Branch  = $branch
            Changes = $changes
        }
    }

    # Resolve mode: default is bidirectional
    $doPull = $Pull -or (-not $Pull -and -not $Push)
    $doPush = $Push -or (-not $Pull -and -not $Push)

    $statusLabel = if ($doPull -and $doPush) { 'Both' } elseif ($doPull) { 'Pulled' } else { 'Pushed' }

    if ($doPull) {
        if ($PSCmdlet.ShouldProcess($repoDir, 'git pull')) {
            $pullOut = & git -C $repoDir pull 2>&1
            $pullOut | ForEach-Object { Write-Verbose $_ }
            if ($LASTEXITCODE -ne 0) {
                script:Out-Err "git pull failed (exit $LASTEXITCODE)"
            } else {
                script:Out-OK 'Pull complete.'
            }
        }
    }

    if ($doPush) {
        if ($PSCmdlet.ShouldProcess($repoDir, 'git add / commit / push')) {
            $addOut = & git -C $repoDir add -A 2>&1
            $addOut | ForEach-Object { Write-Verbose $_ }

            $msg       = "PSSnips sync $(Get-Date -f 'yyyy-MM-dd HH:mm')"
            $commitOut = & git -C $repoDir commit -m $msg 2>&1
            $commitOut | ForEach-Object { Write-Verbose $_ }

            $pushOut = & git -C $repoDir push 2>&1
            $pushOut | ForEach-Object { Write-Verbose $_ }
            if ($LASTEXITCODE -ne 0) {
                script:Out-Err "git push failed (exit $LASTEXITCODE)"
            } else {
                script:Out-OK 'Push complete.'
            }
        }
    }

    # Refresh changed-file count after operations
    $shortAfter = & git -C $repoDir status --short 2>&1
    $changes    = @($shortAfter | Where-Object { $_ -match '\S' }).Count

    return [PSCustomObject]@{
        Status  = $statusLabel
        Branch  = $branch
        Changes = $changes
    }
}