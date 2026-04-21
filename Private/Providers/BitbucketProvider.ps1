# PSSnips — Bitbucket Snippets remote provider
#
# Bitbucket uses PSCredential (Basic auth) rather than a bearer token, and
# its snippet create/update API requires multipart/form-data, so CreateRemote
# and UpdateRemote are not yet implemented here. Use Export-BitbucketSnip /
# Sync-BitbucketSnips wrappers for write operations.

class BitbucketProvider : RemoteProvider {
    hidden [PSCredential] $Cred
    hidden [string]       $Workspace

    BitbucketProvider([PSCredential]$cred, [string]$workspace) {
        $this.ProviderName = 'Bitbucket'
        $this.Cred         = $cred
        $this.Workspace    = $workspace
    }

    [bool] IsConfigured() { return $null -ne $this.Cred }

    [PSCustomObject[]] ListRemote([string]$filter) {
        $base  = 'https://api.bitbucket.org/2.0'
        $ws    = if ($this.Workspace) { $this.Workspace } else { $this.Cred.UserName }
        $uri   = "$base/snippets/$ws"
        $snips = [System.Collections.Generic.List[object]]::new()
        do {
            $page = Invoke-RestMethod -Uri $uri -Method GET -Credential $this.Cred `
                        -Headers @{ 'User-Agent' = 'PSSnips/1.0' } -ErrorAction Stop
            foreach ($v in $page.values) { $snips.Add($v) }
            $uri = if ($page.next) { $page.next } else { $null }
        } while ($uri)

        $results = @($snips | ForEach-Object {
            [PSCustomObject]@{
                Id        = $_.id
                Title     = $_.title
                Scm       = if ($_.scm) { $_.scm } else { 'git' }
                IsPrivate = $_.is_private
                CreatedOn = $_.created_on
                UpdatedOn = $_.updated_on
                Links     = $_.links
            }
        })
        if ($filter) {
            $results = @($results | Where-Object { $_.Title -like "*$filter*" -or $_.Id -like "*$filter*" })
        }
        return $results
    }

    [PSCustomObject] GetRemoteById([string]$id) {
        $base    = 'https://api.bitbucket.org/2.0'
        $ws      = if ($this.Workspace) { $this.Workspace } else { $this.Cred.UserName }
        $encoded = [uri]::EscapeDataString($id)
        return Invoke-RestMethod -Uri "$base/snippets/$ws/$encoded" `
                   -Method GET -Credential $this.Cred `
                   -Headers @{ 'User-Agent' = 'PSSnips/1.0' } -ErrorAction Stop
    }

    [PSCustomObject] CreateRemote([string]$title, [string]$content, [string]$ext, [bool]$isPrivate) {
        # TODO(v3.1): implement multipart form upload; use Export-BitbucketSnip wrapper for now
        throw [System.NotImplementedException]::new('CreateRemote — use Export-BitbucketSnip for Bitbucket snippet creation')
    }

    [void] UpdateRemote([string]$id, [string]$fileKey, [string]$content) {
        # TODO(v3.1): implement multipart form update; use Bitbucket UI or re-export for now
        throw [System.NotImplementedException]::new('UpdateRemote — use Export-BitbucketSnip for Bitbucket snippet updates')
    }

    [PSCustomObject] SyncRemote([string]$localName, [string]$direction) {
        # TODO(v3.1): implement full bidirectional sync here; use Sync-BitbucketSnips wrapper for now
        throw [System.NotImplementedException]::new('SyncRemote — use Sync-BitbucketSnips for Bitbucket sync')
    }
}
