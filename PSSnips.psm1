#Requires -Version 7.0

Set-StrictMode -Version Latest
# $ErrorActionPreference is intentionally NOT set at module scope to avoid bleeding
# into the caller's session. Individual functions use -ErrorAction Stop/Continue as needed.

# Load private files in dependency order
foreach ($file in @(
    'Private\Data.ps1',
    'Private\Logging.ps1',
    'Private\Parsing.ps1',
    'Private\EventDispatch.ps1',
    'Private\IO.ps1',
    'Private\DataStore.ps1',
    'Private\Credentials.ps1',
    'Private\ApiClients.ps1',
    'Private\Fts.ps1',
    'Private\Audit.ps1',
    'Private\Helpers.ps1',
    'Private\Highlighting.ps1'
)) {
    . (Join-Path $PSScriptRoot $file)
}

# Load public files
foreach ($file in @(
    'Public\Config.ps1',
    'Public\Core.ps1',
    'Public\Backup.ps1',
    'Public\GitHub.ps1',
    'Public\GitLab.ps1',
    'Public\Bitbucket.ps1',
    'Public\Sharing.ps1',
    'Public\Profile.ps1',
    'Public\TUI.ps1',
    'Public\Dispatcher.ps1',
    'Public\Analytics.ps1',
    'Public\Templates.ps1',
    'Public\Linting.ps1'
)) {
    . (Join-Path $PSScriptRoot $file)
}

# Argument completers
. (Join-Path $PSScriptRoot 'Private\Completers.ps1')

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

Export-ModuleMember -Function @(
    'Initialize-PSSnips',
    'Get-SnipConfig', 'Set-SnipConfig',
    'Get-Snip', 'Show-Snip', 'New-Snip', 'Add-Snip', 'Remove-Snip', 'Edit-Snip', 'Invoke-Snip', 'Copy-Snip', 'Set-SnipTag',
    'Export-SnipCollection', 'Import-SnipCollection',
    'Get-GistList', 'Get-Gist', 'Import-Gist', 'Export-Gist', 'Invoke-Gist', 'Sync-Gist',
    'Get-GitLabSnipList', 'Get-GitLabSnip', 'Import-GitLabSnip', 'Export-GitLabSnip',
    'Get-BitbucketSnipList', 'Import-BitbucketSnip', 'Export-BitbucketSnip', 'Sync-BitbucketSnips',
    'Publish-Snip', 'Sync-SharedSnips',
    'Install-PSSnips', 'Uninstall-PSSnips',
    'Start-SnipManager',
    'Get-SnipHistory', 'Restore-Snip', 'Test-Snip',
    'Invoke-SnipCLI',
    'Get-StaleSnip', 'Get-SnipStats', 'Export-VSCodeSnips', 'Invoke-FuzzySnip',
    'Add-SnipTerminalProfile',
    'Get-SnipAuditLog',
    'Set-SnipRating', 'Add-SnipComment',
    'New-SnipFromTemplate', 'Get-SnipTemplate',
    'New-SnipSchedule', 'Get-SnipSchedule', 'Remove-SnipSchedule',
    'Initialize-SnipPreCommitHook',
    'Sync-SnipMetadata',
    'Register-SnipEvent', 'Unregister-SnipEvent',
    'Invoke-SnipLint', 'Test-SnipLint'
) -Alias 'snip'
