# PSSnips — GitLab Snippets integration.

function Get-GitLabSnipList {
    <#
    .SYNOPSIS
        Lists GitLab snippets for the authenticated user.
    .DESCRIPTION
        Calls the GitLab Snippets API (GET /api/v4/snippets) and displays a formatted
        table of snippets showing ID, Title, Visibility, and FileName.
    .PARAMETER Filter
        Optional substring to match against title and file_name.
    .PARAMETER Count
        Optional. Maximum number of snippets to retrieve. Default: 30.
    .EXAMPLE
        Get-GitLabSnipList
    .EXAMPLE
        Get-GitLabSnipList -Filter 'deploy' -Count 50
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Filter = '',
        [uint32]$Count  = 30
    )
    script:InitEnv
    $p = script:Get-RemoteProvider -Name 'GitLab'
    if (-not $p.IsConfigured()) { script:Out-Err 'GitLab credentials not configured. Run Set-SnipConfig -GitLabToken <token>.'; return }
    try {
        $snips = @($p.ListRemote($Filter))
    } catch { Write-Error "GitLab API error: $_" -ErrorAction Continue; return }
    if ([int]$Count -lt $snips.Count) { $snips = $snips[0..([int]$Count - 1)] }
    if (-not $snips -or $snips.Count -eq 0) { script:Out-Info "No GitLab snippets found."; return }

    Write-Host ""
    Write-Host ("  {0,-10} {1,-40} {2,-10} {3}" -f 'ID','TITLE','VISIBILITY','FILENAME') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 80)" -ForegroundColor DarkGray
    foreach ($s in $snips) {
        $fn = if ($s.file_name) { $s.file_name } else { '' }
        Write-Host ("  {0,-10} {1,-40} {2,-10} {3}" -f $s.id, $s.title, $s.visibility, $fn) -ForegroundColor Gray
    }
    Write-Host ""
    return $snips
}

function Get-GitLabSnip {
    <#
    .SYNOPSIS
        Fetches and displays a specific GitLab snippet by ID.
    .DESCRIPTION
        Calls GET /api/v4/snippets/<id> and GET /api/v4/snippets/<id>/raw,
        returning the snippet object with RawContent added.
    .PARAMETER SnipId
        Mandatory. The GitLab snippet ID.
    .EXAMPLE
        Get-GitLabSnip 12345
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='GitLab snippet ID')]
        [ValidateNotNullOrEmpty()]
        [string]$SnipId
    )
    script:InitEnv
    $p = script:Get-RemoteProvider -Name 'GitLab'
    try {
        $snip = $p.GetRemoteById($SnipId)
    } catch { Write-Error "GitLab API error: $_" -ErrorAction Continue; return }
    $raw = $snip.RawContent

    $snip | Add-Member -NotePropertyName RawContent -NotePropertyValue $raw -Force
    Write-Host ""
    Write-Host ("  Snippet: {0} (ID: {1})" -f $snip.title, $SnipId) -ForegroundColor Cyan
    if ($snip.description) { Write-Host "  $($snip.description)" -ForegroundColor Gray }
    Write-Host "  $($snip.web_url)" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host $raw
    Write-Host ""
    return $snip
}

function Import-GitLabSnip {
    <#
    .SYNOPSIS
        Downloads a GitLab snippet and saves it as a local snippet.
    .DESCRIPTION
        Fetches the raw content from /api/v4/snippets/<id>/raw and metadata from
        /api/v4/snippets/<id>, then saves to local snippets dir and registers in
        the index with gitlabId and gitlabUrl fields.
    .PARAMETER SnipId
        Mandatory. The GitLab snippet ID to import.
    .PARAMETER Name
        Optional. Override the local snippet name.
    .PARAMETER Force
        Optional switch. Overwrites existing snippet with the same name.
    .EXAMPLE
        Import-GitLabSnip 12345
    .EXAMPLE
        Import-GitLabSnip 12345 -Name my-local-name -Force
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
        The gitlabId and gitlabUrl are stored in the index for future sync.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='GitLab snippet ID to import')]
        [ValidateNotNullOrEmpty()]
        [string]$SnipId,
        [string]$Name  = '',
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg
    $p   = script:Get-RemoteProvider -Name 'GitLab'
    try {
        $meta = $p.GetRemoteById($SnipId)
        $raw  = $meta.RawContent
    } catch { Write-Error "GitLab API error: $_" -ErrorAction Continue; return }

    $fn       = if ($meta.file_name) { $meta.file_name } else { 'snippet.txt' }
    $ext      = [System.IO.Path]::GetExtension($fn).TrimStart('.')
    if (-not $ext) { $ext = 'txt' }
    $snipName = if ($Name) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($fn) }

    $idx = script:LoadIdx
    # Deduplicate name
    if ($idx.snippets.ContainsKey($snipName) -and -not $Force) {
        $base = $snipName; $n = 1
        while ($idx.snippets.ContainsKey($snipName)) { $snipName = "$base-$n"; $n++ }
    }

    Set-Content (Join-Path $cfg.SnippetsDir "$snipName.$ext") -Value $raw -Encoding UTF8
    $glMeta = [SnippetMetadata]::new()
    $glMeta.Name        = $snipName
    $glMeta.Description = if ($meta.description) { $meta.description } else { if ($meta.title) { $meta.title } else { '' } }
    $glMeta.Language    = $ext
    $glMeta.ContentHash = script:GetContentHash -Content $raw
    Add-Member -InputObject $glMeta -NotePropertyName 'GitLabId'  -NotePropertyValue $SnipId -Force
    Add-Member -InputObject $glMeta -NotePropertyName 'GitLabUrl' -NotePropertyValue (if ($meta.web_url) { $meta.web_url } else { '' }) -Force
    $idx.snippets[$snipName] = $glMeta
    script:SaveIdx -Idx $idx
    script:Out-OK "Imported GitLab snippet '$snipName' ($ext)."
    script:Write-AuditLog -Operation 'Import' -SnippetName $snipName
}

function Export-GitLabSnip {
    <#
    .SYNOPSIS
        Exports a local snippet to GitLab as a new or updated snippet.
    .DESCRIPTION
        Creates (POST /api/v4/snippets) or updates (PUT /api/v4/snippets/<id>) a
        GitLab snippet. After success, saves gitlabId and gitlabUrl to the index.
    .PARAMETER Name
        Mandatory. The local snippet name to export.
    .PARAMETER Description
        Optional. Description for the GitLab snippet.
    .PARAMETER Visibility
        Optional. 'public', 'internal', or 'private'. Default: 'private'.
    .EXAMPLE
        Export-GitLabSnip my-snippet
    .EXAMPLE
        Export-GitLabSnip my-snippet -Description 'Deploy script' -Visibility internal
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires GitLabToken config or $env:GITLAB_TOKEN.
        If snippet already has a gitlabId, the existing GitLab snippet is updated.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Local snippet name to export')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Description = '',
        [ValidateSet('public','internal','private')]
        [string]$Visibility  = 'private'
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $meta    = $idx.snippets[$Name]
    $path    = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet file for '$Name' not found." -ErrorAction Continue; return }
    $content = Get-Content $path -Raw -Encoding UTF8
    $fn      = "$Name.$($meta.Language)"
    $desc    = if ($Description) { $Description } elseif ($meta.Description) { $meta.Description } else { $Name }

    $p    = script:Get-RemoteProvider -Name 'GitLab'
    if (-not $p.IsConfigured()) { Write-Error "GitLab credentials not configured. Run Set-SnipConfig -GitLabToken <token>." -ErrorAction Continue; return }
    $glId = if ($null -ne $meta.PSObject.Properties['GitLabId'] -and $meta.GitLabId) { $meta.GitLabId } else { $null }
    try {
        if ($glId) {
            $p.UpdateRemote($glId, $fn, $content)
            $glUrl = if ($null -ne $meta.PSObject.Properties['GitLabUrl']) { $meta.GitLabUrl } else { '' }
        } else {
            $result = $p.CreateRemote($desc, $content, $meta.Language, ($Visibility -eq 'private'))
            $idx.snippets[$Name].GitLabId  = $result.Id
            $idx.snippets[$Name].GitLabUrl = $result.Url
            script:SaveIdx -Idx $idx
            $glUrl = $result.Url
        }
        script:Out-OK "GitLab snippet $(if ($glId) {'updated'} else {'created'}): $glUrl"
        script:Write-AuditLog -Operation 'Export' -SnippetName $Name
        script:Invoke-SnipEvent -EventName 'SnipPublished' -Data @{
            Name     = $Name
            Provider = 'gitlab'
            Url      = $glUrl
        }
    } catch { Write-Error "Failed to export to GitLab: $_" -ErrorAction Continue }
}

