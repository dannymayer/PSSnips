# PSSnips — GitLab Snippets remote provider
#
# API calls are delegated via $script:_CallGitLabDelegate so class methods can
# reach the module-scoped script:CallGitLab function.

class GitLabProvider : RemoteProvider {
    hidden [string] $Token
    hidden [string] $Url

    GitLabProvider([string]$token, [string]$url) {
        $this.ProviderName = 'GitLab'
        $this.Token        = $token
        $this.Url          = if ($url) { $url } else { 'https://gitlab.com' }
    }

    [bool] IsConfigured() { return [bool]$this.Token }

    [PSCustomObject[]] ListRemote([string]$filter) {
        $snips = @(& $script:_CallGitLabDelegate 'snippets?per_page=100' 'GET' $null)
        if ($filter) {
            $snips = @($snips | Where-Object { $_.title -like "*$filter*" -or $_.file_name -like "*$filter*" })
        }
        return $snips
    }

    # Returns the snippet object with a RawContent note property added.
    [PSCustomObject] GetRemoteById([string]$id) {
        $snip = & $script:_CallGitLabDelegate "snippets/$id" 'GET' $null
        $raw  = & $script:_CallGitLabDelegate "snippets/$id/raw" 'GET' $null
        $snip | Add-Member -NotePropertyName 'RawContent' -NotePropertyValue $raw -Force
        return $snip
    }

    # Returns [PSCustomObject]@{ Id; Url } after creating the snippet.
    # isPrivate=true → 'private', isPrivate=false → 'public'.
    [PSCustomObject] CreateRemote([string]$title, [string]$content, [string]$ext, [bool]$isPrivate) {
        $fn   = "$title.$ext"
        $body = @{
            title      = $title
            visibility = if ($isPrivate) { 'private' } else { 'public' }
            files      = @(@{ file_path = $fn; content = $content })
        }
        $r = & $script:_CallGitLabDelegate 'snippets' 'POST' $body
        return [PSCustomObject]@{ Id = $r.id; Url = if ($r.web_url) { $r.web_url } else { '' } }
    }

    # $fileKey is the file_path in the GitLab files array.
    [void] UpdateRemote([string]$id, [string]$fileKey, [string]$content) {
        $body = @{ files = @(@{ file_path = $fileKey; content = $content }) }
        $null = & $script:_CallGitLabDelegate "snippets/$id" 'PUT' $body
    }

    [PSCustomObject] SyncRemote([string]$localName, [string]$direction) {
        # TODO(v3.1): implement full bidirectional sync here; Sync-RemoteSnip falls back to provider-specific functions
        throw [System.NotImplementedException]::new('SyncRemote — use Export-GitLabSnip / Import-GitLabSnip for GitLab sync')
    }
}
