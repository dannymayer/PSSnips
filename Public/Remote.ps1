# PSSnips — Unified remote provider public API

function Get-RemoteSnip {
    <#
    .SYNOPSIS
        Lists or retrieves snippets from a remote provider (GitHub, GitLab, or Bitbucket).
    .DESCRIPTION
        Provides a unified interface for retrieving remote snippets regardless of provider.
        Use -Id to retrieve a specific snippet, or -Filter to search by title/description.
        The shape of the returned objects varies by provider (GitHub Gist objects,
        GitLab Snippet objects, or Bitbucket Snippet objects).
    .PARAMETER Provider
        The remote provider to query. Defaults to GitHub.
    .PARAMETER Id
        The ID of a specific remote snippet or gist to retrieve.
    .PARAMETER Filter
        Optional filter string to narrow the listing.
    .EXAMPLE
        Get-RemoteSnip -Provider GitHub
        Lists all your GitHub gists.
    .EXAMPLE
        Get-RemoteSnip -Provider GitLab -Id 12345
        Retrieves a specific GitLab snippet.
    .EXAMPLE
        Get-RemoteSnip -Provider Bitbucket -Filter 'deploy'
        Lists Bitbucket snippets whose title contains 'deploy'.
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires the corresponding provider credentials to be configured.
        GitHub: Set-SnipConfig -GitHubToken
        GitLab: Set-SnipConfig -GitLabToken
        Bitbucket: Set-SnipConfig -BitbucketUsername / -BitbucketAppPassword
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateSet('GitHub', 'GitLab', 'Bitbucket')]
        [string]$Provider = 'GitHub',
        [string]$Id       = '',
        [string]$Filter   = ''
    )
    script:InitEnv
    $p = script:Get-RemoteProvider -Name $Provider
    if (-not $p.IsConfigured()) {
        script:Out-Err "$Provider credentials not configured. Use Set-SnipConfig to add your token."
        return
    }
    if ($Id) {
        return $p.GetRemoteById($Id)
    }
    return $p.ListRemote($Filter)
}

function Sync-RemoteSnip {
    <#
    .SYNOPSIS
        Synchronises a local snippet with a remote provider.
    .DESCRIPTION
        Pushes, pulls, or bidirectionally syncs a named local snippet with its
        linked remote entry on GitHub Gists, GitLab Snippets, or Bitbucket Snippets.
        Provider-specific sync functions (Sync-Gist, Export/Import-GitLabSnip,
        Sync-BitbucketSnips) are used as the implementation until full SyncRemote
        support is added to the provider classes in a future release.
    .PARAMETER Name
        The local snippet name.
    .PARAMETER Provider
        The remote provider. Defaults to GitHub.
    .PARAMETER Direction
        Push (local→remote), Pull (remote→local), or Both (bidirectional). Defaults to Both.
    .EXAMPLE
        Sync-RemoteSnip -Name 'deploy-script' -Provider GitHub
        Bidirectionally syncs the local 'deploy-script' snippet with GitHub Gists.
    .EXAMPLE
        Sync-RemoteSnip -Name 'my-query' -Provider GitLab -Direction Push
        Pushes 'my-query' to GitLab.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        The snippet must already have a linked remote ID. For GitHub, run Export-Gist
        first. For GitLab, run Export-GitLabSnip first.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [ValidateSet('GitHub', 'GitLab', 'Bitbucket')]
        [string]$Provider  = 'GitHub',
        [ValidateSet('Push', 'Pull', 'Both')]
        [string]$Direction = 'Both'
    )
    script:InitEnv
    $p = script:Get-RemoteProvider -Name $Provider
    if (-not $p.IsConfigured()) {
        script:Out-Err "$Provider credentials not configured."
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, "Sync with $Provider ($Direction)")) { return }

    try {
        $result = $p.SyncRemote($Name, $Direction)
        script:Out-OK "Sync complete — pushed: $($result.Pushed), pulled: $($result.Pulled)"
        if ($result.Conflicts) {
            script:Out-Warn "Conflicts detected: $($result.Conflicts -join ', ')"
        }
    } catch [System.NotImplementedException] {
        # TODO(v3.1): remove this fallback once SyncRemote is implemented in each provider
        $idx = script:LoadIdx
        switch ($Provider) {
            'GitHub' {
                if (-not $idx.snippets.ContainsKey($Name)) {
                    script:Out-Err "Snippet '$Name' not found."; return
                }
                if ($Direction -in 'Push', 'Both') { Export-Gist -Name $Name }
                if ($Direction -in 'Pull', 'Both') {
                    if ($idx.snippets[$Name].GistId) {
                        Import-Gist -GistId $idx.snippets[$Name].GistId -Name $Name -Force
                    } else {
                        script:Out-Warn "'$Name' has no linked Gist for pull. Run Export-Gist first."
                    }
                }
                script:Out-OK "GitHub sync complete for '$Name'."
            }
            'GitLab' {
                if (-not $idx.snippets.ContainsKey($Name)) {
                    script:Out-Err "Snippet '$Name' not found."; return
                }
                if ($Direction -in 'Push', 'Both') { Export-GitLabSnip -Name $Name }
                if ($Direction -in 'Pull', 'Both') {
                    $glId = if ($null -ne $idx.snippets[$Name].PSObject.Properties['GitLabId']) { $idx.snippets[$Name].GitLabId } else { $null }
                    if ($glId) {
                        Import-GitLabSnip -SnipId $glId -Name $Name -Force
                    } else {
                        script:Out-Warn "'$Name' has no linked GitLab snippet for pull. Run Export-GitLabSnip first."
                    }
                }
                script:Out-OK "GitLab sync complete for '$Name'."
            }
            'Bitbucket' {
                Sync-BitbucketSnips -Direction $Direction
            }
        }
    }
}
