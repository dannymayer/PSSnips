# PSSnips — Core data model classes

class SnippetMetadata {
    [string]             $Name        = ''
    [string]             $Language    = ''
    [string[]]           $Tags        = @()
    [string]             $Description = ''
    [datetime]           $Created
    [datetime]           $Modified
    [string]             $GistId      = ''
    [string]             $GistUrl     = ''
    [string]             $ContentHash = ''
    [int]                $RunCount    = 0
    [nullable[datetime]] $LastRun     = $null
    [bool]               $Pinned      = $false
    [int]                $Rating      = 0
    [string[]]           $Comments    = @()
    [string]             $CreatedBy   = ''
    [string]             $UpdatedBy   = ''
    [string[]]           $Platforms   = @()

    SnippetMetadata() {
        $now = Get-Date
        $this.Created  = $now
        $this.Modified = $now
    }

    # Builds from the hashtable that ConvertFrom-Json -AsHashtable produces.
    # Handles missing keys gracefully for old index.json compatibility.
    static [SnippetMetadata] FromHashtable([hashtable]$ht) {
        $sm             = [SnippetMetadata]::new()
        $sm.Name        = if ($ht.ContainsKey('name'))        { [string]$ht['name'] }        else { '' }
        $sm.Language    = if ($ht.ContainsKey('language'))    { [string]$ht['language'] }    else { '' }
        $sm.Tags        = if ($ht.ContainsKey('tags'))        { @($ht['tags']) }             else { @() }
        $sm.Description = if ($ht.ContainsKey('description')) { [string]$ht['description'] } else { '' }
        $sm.GistId      = if ($ht.ContainsKey('gistId'))      { [string]$ht['gistId'] }      else { '' }
        $sm.GistUrl     = if ($ht.ContainsKey('gistUrl'))     { [string]$ht['gistUrl'] }     else { '' }
        $sm.ContentHash = if ($ht.ContainsKey('contentHash')) { [string]$ht['contentHash'] } else { '' }
        $sm.RunCount    = if ($ht.ContainsKey('runCount'))    { [int]$ht['runCount'] }        else { 0 }
        $sm.Pinned      = if ($ht.ContainsKey('pinned'))      { [bool]$ht['pinned'] }         else { $false }
        $sm.Rating      = if ($ht.ContainsKey('rating'))      { [int]$ht['rating'] }          else { 0 }
        $sm.Comments    = if ($ht.ContainsKey('comments'))    { @($ht['comments']) }          else { @() }
        $sm.CreatedBy   = if ($ht.ContainsKey('createdBy'))   { [string]$ht['createdBy'] }   else { '' }
        $sm.UpdatedBy   = if ($ht.ContainsKey('updatedBy'))   { [string]$ht['updatedBy'] }   else { '' }
        $sm.Platforms   = if ($ht.ContainsKey('platforms'))   { @($ht['platforms']) }         else { @() }
        if ($ht.ContainsKey('created')  -and $ht['created'])  { try { $sm.Created  = [datetime]$ht['created']  } catch { Write-Verbose "SnippetMetadata: could not parse 'created': $_" } }
        if ($ht.ContainsKey('modified') -and $ht['modified']) { try { $sm.Modified = [datetime]$ht['modified'] } catch { Write-Verbose "SnippetMetadata: could not parse 'modified': $_" } }
        if ($ht.ContainsKey('lastRun')  -and $ht['lastRun'])  { try { $sm.LastRun  = [datetime]$ht['lastRun']  } catch { Write-Verbose "SnippetMetadata: could not parse 'lastRun': $_" } }
        # Preserve provider-specific extra fields (gitlabId, bitbucketId, etc.)
        if ($ht.ContainsKey('gitlabId'))    { Add-Member -InputObject $sm -NotePropertyName 'GitLabId'    -NotePropertyValue $ht['gitlabId']    -Force }
        if ($ht.ContainsKey('bitbucketId')) { Add-Member -InputObject $sm -NotePropertyName 'BitbucketId' -NotePropertyValue $ht['bitbucketId'] -Force }
        return $sm
    }

    # Produces the hashtable that ConvertTo-Json will write to index.json.
    [hashtable] ToHashtable() {
        $ht = [ordered]@{
            name        = $this.Name
            language    = $this.Language
            tags        = $this.Tags
            description = $this.Description
            created     = $this.Created.ToString('o')
            modified    = $this.Modified.ToString('o')
            gistId      = $this.GistId
            gistUrl     = $this.GistUrl
            contentHash = $this.ContentHash
            runCount    = $this.RunCount
            pinned      = $this.Pinned
            rating      = $this.Rating
            comments    = $this.Comments
            createdBy   = $this.CreatedBy
            updatedBy   = $this.UpdatedBy
            platforms   = $this.Platforms
        }
        if ($null -ne $this.LastRun) { $ht['lastRun'] = ([datetime]$this.LastRun).ToString('o') }
        # Preserve any extra NoteProperties added by providers
        $this.PSObject.Properties |
            Where-Object { $_.MemberType -eq 'NoteProperty' -and -not $ht.ContainsKey($_.Name) } |
            ForEach-Object { $ht[$_.Name] = $_.Value }
        return $ht
    }
}
