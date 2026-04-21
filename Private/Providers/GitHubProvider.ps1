# PSSnips — GitHub Gist remote provider
#
# API calls are delegated via $script:_CallGitHubDelegate so class methods can
# reach the module-scoped script:CallGitHub function.

class GitHubProvider : RemoteProvider {
    hidden [string] $Token
    hidden [string] $Username

    GitHubProvider([string]$token, [string]$username) {
        $this.ProviderName = 'GitHub'
        $this.Token        = $token
        $this.Username     = $username
    }

    [bool] IsConfigured() { return [bool]$this.Token }

    [PSCustomObject[]] ListRemote([string]$filter) {
        $ep    = if ($this.Username) { "users/$($this.Username)/gists?per_page=100" } else { 'gists?per_page=100' }
        $gists = @(& $script:_CallGitHubDelegate $ep 'GET' $null)
        if ($filter) {
            $gists = @($gists | Where-Object {
                $_.description -like "*$filter*" -or
                ($_.files.PSObject.Properties.Name | Where-Object { $_ -like "*$filter*" })
            })
        }
        return $gists
    }

    [PSCustomObject] GetRemoteById([string]$id) {
        return & $script:_CallGitHubDelegate "gists/$id" 'GET' $null
    }

    # Returns [PSCustomObject]@{ Id; Url } after creating the gist.
    # $title is used as both the gist description and the filename prefix.
    [PSCustomObject] CreateRemote([string]$title, [string]$content, [string]$ext, [bool]$isPrivate) {
        $fn   = "$title.$ext"
        $body = @{
            description = $title
            public      = -not $isPrivate
            files       = @{ $fn = @{ content = $content } }
        }
        $r = & $script:_CallGitHubDelegate 'gists' 'POST' $body
        return [PSCustomObject]@{ Id = $r.id; Url = $r.html_url }
    }

    # $fileKey is the filename key in the gist files hash (e.g. "my-snippet.ps1").
    [void] UpdateRemote([string]$id, [string]$fileKey, [string]$content) {
        $body = @{ files = @{ $fileKey = @{ content = $content } } }
        $null = & $script:_CallGitHubDelegate "gists/$id" 'PATCH' $body
    }

    [PSCustomObject] SyncRemote([string]$localName, [string]$direction) {
        # TODO(v3.1): implement full bidirectional sync here; Sync-RemoteSnip falls back to Sync-Gist
        throw [System.NotImplementedException]::new('SyncRemote — use Sync-Gist for GitHub sync')
    }
}
