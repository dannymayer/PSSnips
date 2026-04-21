# PSSnips — Bitbucket Snippets integration.
function Get-BitbucketSnipList {
    <#
    .SYNOPSIS
        Lists Bitbucket snippets for the authenticated user or a specific workspace.
    .DESCRIPTION
        Calls the Bitbucket Snippets API (GET /2.0/snippets/{workspace} or
        /2.0/snippets) and displays a formatted table of snippets showing Id, Title,
        Created, Updated, and IsPrivate columns.
    .PARAMETER Workspace
        Optional. The Bitbucket workspace slug to list snippets from. Defaults to
        the authenticated user's workspace (their username).
    .PARAMETER Role
        Optional. Filter by role. Accepted values: 'owner', 'contributor', 'member'.
        Maps to the Bitbucket API 'role' query parameter.
    .EXAMPLE
        Get-BitbucketSnipList
    .EXAMPLE
        Get-BitbucketSnipList -Workspace myteam -Role owner
    .INPUTS
        None.
    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
    .NOTES
        Requires BitbucketUsername + BitbucketAppPassword config or
        $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Workspace = '',
        [ValidateSet('owner','contributor','member','')]
        [string]$Role      = ''
    )
    script:InitEnv
    $p = script:Get-RemoteProvider -Name 'Bitbucket'
    if (-not $p.IsConfigured()) { script:Out-Warn 'Bitbucket credentials not set. Run: Set-SnipConfig -BitbucketUsername <user> -BitbucketAppPassword <app-pwd>  (or set $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD)'; return }

    $effectiveWs = if ($Workspace) { $Workspace } else { $null }
    if ($effectiveWs) {
        # Use a workspace-specific provider instance
        $cred = script:GetBitbucketCreds
        if (-not $cred) { return }
        $p = [BitbucketProvider]::new($cred, $effectiveWs)
    }

    try {
        $snips = @($p.ListRemote(''))
    } catch {
        script:Out-Err "Bitbucket API error: $_"
        return
    }
    if ($Role) {
        # Re-query with role filter since the provider uses a simple endpoint
        $cred = script:GetBitbucketCreds
        if (-not $cred) { return }
        $uri  = "https://api.bitbucket.org/2.0/snippets/$(if ($Workspace) { $Workspace } else { $cred.UserName })?role=$Role"
        $rawSnips = [System.Collections.Generic.List[object]]::new()
        try {
            do {
                $page = Invoke-RestMethod -Uri $uri -Method GET -Credential $cred `
                            -Headers @{ 'User-Agent' = 'PSSnips/1.0' } -ErrorAction Stop
                foreach ($v in $page.values) { $rawSnips.Add($v) }
                $uri = if ($page.next) { $page.next } else { $null }
            } while ($uri)
        } catch {
            script:Out-Err "Bitbucket API error: $_"
            return
        }
        $snips = @($rawSnips | ForEach-Object {
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
    }

    if ($snips.Count -eq 0) { script:Out-Info 'No Bitbucket snippets found.'; return }

    Write-Host ''
    Write-Host ("  {0,-12} {1,-40} {2,-22} {3,-22} {4}" -f 'ID','TITLE','CREATED','UPDATED','PRIVATE') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 105)" -ForegroundColor DarkGray
    foreach ($s in $snips) {
        $created  = if ($s.CreatedOn)  { [datetime]$s.CreatedOn  | Get-Date -Format 'yyyy-MM-dd HH:mm' } else { '' }
        $updated  = if ($s.UpdatedOn)  { [datetime]$s.UpdatedOn  | Get-Date -Format 'yyyy-MM-dd HH:mm' } else { '' }
        $isPriv   = if ($s.IsPrivate)  { 'Yes' } else { 'No' }
        Write-Host ("  {0,-12} {1,-40} {2,-22} {3,-22} {4}" -f $s.Id, $s.Title, $created, $updated, $isPriv) -ForegroundColor Gray
    }
    Write-Host ''

    return $snips
}

function Import-BitbucketSnip {
    <#
    .SYNOPSIS
        Downloads a Bitbucket snippet and saves it as one or more local snippets.
    .DESCRIPTION
        Fetches the snippet metadata from GET /2.0/snippets/{workspace}/{encoded_id}
        and then retrieves each file's content via the file self-link. If the snippet
        contains multiple files each is saved as a separate local snippet named
        {Name}-{filename} (or {title}-{filename} when -Name is not provided).
        Each file is registered via New-Snip with -Content and optional -Force.
    .PARAMETER Id
        Mandatory. The short alphanumeric Bitbucket snippet ID (e.g., 'xKjP9').
    .PARAMETER Workspace
        Optional. The Bitbucket workspace slug. Defaults to the authenticated user's
        username.
    .PARAMETER Name
        Optional. Override for the local snippet base name. When the snippet has
        multiple files, each file is saved as {Name}-{filename}.
    .PARAMETER Force
        Optional switch. Overwrites existing local snippets with the same name.
    .EXAMPLE
        Import-BitbucketSnip -Id xKjP9
    .EXAMPLE
        Import-BitbucketSnip -Id xKjP9 -Workspace myteam -Name my-local -Force
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires BitbucketUsername + BitbucketAppPassword config or
        $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD.
        The bitbucketId is stored in the index for future sync.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Bitbucket snippet ID (e.g. xKjP9)')]
        [ValidateNotNullOrEmpty()]
        [string]$Id,
        [string]$Workspace = '',
        [string]$Name      = '',
        [switch]$Force
    )
    script:InitEnv
    $p    = script:Get-RemoteProvider -Name 'Bitbucket'
    if (-not $p.IsConfigured()) { script:Out-Warn 'Bitbucket credentials not set. Run: Set-SnipConfig -BitbucketUsername <user> -BitbucketAppPassword <app-pwd>  (or set $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD)'; return }
    $cred = script:GetBitbucketCreds
    if (-not $cred) { return }

    $bbProvider = if ($Workspace) { [BitbucketProvider]::new($cred, $Workspace) } else { $p }

    try {
        $meta = $bbProvider.GetRemoteById($Id)
    } catch {
        script:Out-Err "Bitbucket API error fetching snippet '$Id': $_"
        return
    }

    $baseName = if ($Name) { $Name } else {
        $meta.title -replace '[^\w\-]', '-' -replace '-{2,}', '-' -replace '^-|-$', ''
    }
    if (-not $baseName) { $baseName = $Id }

    $fileNames = @($meta.files.PSObject.Properties.Name)
    if ($fileNames.Count -eq 0) {
        script:Out-Warn "Snippet '$Id' has no files."
        return
    }

    foreach ($fileName in $fileNames) {
        $fileLink = $meta.files.$fileName.links.self.href
        try {
            $rawContent = Invoke-RestMethod -Uri $fileLink -Method GET -Credential $cred `
                              -Headers @{ 'User-Agent' = 'PSSnips/1.0' } -ErrorAction Stop
        } catch {
            script:Out-Err "Failed to fetch file '$fileName' for snippet '$Id': $_"
            continue
        }

        $ext      = [System.IO.Path]::GetExtension($fileName).TrimStart('.')
        if (-not $ext) { $ext = 'txt' }
        $fileBase = [System.IO.Path]::GetFileNameWithoutExtension($fileName)

        $snipName = if ($fileNames.Count -eq 1) {
            $baseName
        } else {
            "$baseName-$fileBase"
        }

        $params = @{
            Name     = $snipName
            Language = $ext
            Content  = if ($rawContent -is [string]) { $rawContent } else { $rawContent | Out-String }
            Force    = $Force
        }
        New-Snip @params

        # Stamp the bitbucketId into the index entry
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($snipName)) {
            Add-Member -InputObject $idx.snippets[$snipName] -NotePropertyName 'BitbucketId'  -NotePropertyValue $Id -Force
            Add-Member -InputObject $idx.snippets[$snipName] -NotePropertyName 'BitbucketUrl' -NotePropertyValue (if ($meta.links.html.href) { $meta.links.html.href } else { '' }) -Force
            script:SaveIdx -Idx $idx
        }
        script:Out-OK "Imported Bitbucket snippet '$snipName' ($ext)."
    }
}

function Export-BitbucketSnip {
    <#
    .SYNOPSIS
        Exports a local snippet to Bitbucket as a new snippet.
    .DESCRIPTION
        Reads the local snippet content and POSTs it to
        POST /2.0/snippets/{workspace} as multipart/form-data. On success the new
        snippet URL is displayed and the bitbucketId / bitbucketUrl are saved to the
        local index. A temporary staging file is created inside the PSSnips home
        directory and removed immediately after the upload.
    .PARAMETER Name
        Mandatory. The local snippet name to upload.
    .PARAMETER Title
        Optional. The title to use on Bitbucket. Defaults to the snippet name.
    .PARAMETER IsPrivate
        Optional switch. When specified the snippet is created as private (not public).
    .EXAMPLE
        Export-BitbucketSnip my-snippet
    .EXAMPLE
        Export-BitbucketSnip my-snippet -Title 'Deploy script' -IsPrivate
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires BitbucketUsername + BitbucketAppPassword config or
        $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD.
        If the snippet already has a bitbucketId it is reported as already exported;
        use the Bitbucket UI to update existing snippets or delete and re-export.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Local snippet name to export')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Title = '',
        [switch]$IsPrivate
    )
    script:InitEnv
    $p = script:Get-RemoteProvider -Name 'Bitbucket'
    if (-not $p.IsConfigured()) { script:Out-Warn 'Bitbucket credentials not set. Run: Set-SnipConfig -BitbucketUsername <user> -BitbucketAppPassword <app-pwd>  (or set $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD)'; return }
    $cred = script:GetBitbucketCreds
    if (-not $cred) { return }

    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) {
        Write-Error "Snippet '$Name' not found." -ErrorAction Continue
        return
    }

    $meta    = $idx.snippets[$Name]
    $path    = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) {
        Write-Error "Snippet file for '$Name' not found." -ErrorAction Continue
        return
    }

    $content      = Get-Content $path -Raw -Encoding UTF8
    $fn           = "$Name.$($meta.Language)"
    $effectTitle  = if ($Title) { $Title } else { $Name }
    $base         = 'https://api.bitbucket.org/2.0'
    $workspace    = $cred.UserName

    # Write content to a staging file named after the snippet so Bitbucket
    # receives the correct filename in the multipart Content-Disposition header.
    $stagingFile  = Join-Path $script:Home "._export_$fn"
    try {
        Set-Content $stagingFile -Value $content -Encoding UTF8 -NoNewline

        $form = @{
            title      = $effectTitle
            is_private = if ($IsPrivate) { 'true' } else { 'false' }
            $fn        = Get-Item $stagingFile
        }

        $result = Invoke-RestMethod -Uri "$base/snippets/$workspace" `
                      -Method POST -Credential $cred `
                      -Headers @{ 'User-Agent' = 'PSSnips/1.0' } `
                      -Form $form -ErrorAction Stop

        $idx.snippets[$Name].BitbucketId  = $result.id
        $idx.snippets[$Name].BitbucketUrl = if ($result.links.html.href) { $result.links.html.href } else { '' }
        script:SaveIdx -Idx $idx
        script:Out-OK "Bitbucket snippet created: $($result.links.html.href)"
        script:Invoke-SnipEvent -EventName 'SnipPublished' -Data @{
            Name     = $Name
            Provider = 'bitbucket'
            Url      = ''
        }
    } catch {
        script:Out-Err "Failed to export '$Name' to Bitbucket: $_"
    } finally {
        if (Test-Path $stagingFile) { Remove-Item $stagingFile -Force }
    }
}

function Sync-BitbucketSnips {
    <#
    .SYNOPSIS
        Synchronises local snippets with Bitbucket in one or both directions.
    .DESCRIPTION
        Pull downloads all Bitbucket snippets found via Get-BitbucketSnipList and
        imports each with Import-BitbucketSnip. Push uploads every local snippet
        that does not yet have a bitbucketId via Export-BitbucketSnip. Both runs
        Pull then Push in sequence.
    .PARAMETER Workspace
        Optional. The Bitbucket workspace slug. Defaults to the authenticated user's
        username.
    .PARAMETER Direction
        Optional. 'Pull' (default), 'Push', or 'Both'.
    .PARAMETER Force
        Optional switch. Passed through to Import-BitbucketSnip to allow overwriting
        existing local snippets during a Pull.
    .EXAMPLE
        Sync-BitbucketSnips
    .EXAMPLE
        Sync-BitbucketSnips -Direction Both -Force
    .EXAMPLE
        Sync-BitbucketSnips -Direction Push -Workspace myteam
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Requires BitbucketUsername + BitbucketAppPassword config or
        $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD.
    #>
    [CmdletBinding()]
    param(
        [string]$Workspace = '',
        [ValidateSet('Pull','Push','Both')]
        [string]$Direction = 'Pull',
        [switch]$Force
    )
    script:InitEnv
    $cred = script:GetBitbucketCreds
    if (-not $cred) { return }

    $ws = if ($Workspace) { $Workspace } else { $cred.UserName }

    if ($Direction -in 'Pull','Both') {
        script:Out-Info 'Pulling snippets from Bitbucket…'
        $remote = Get-BitbucketSnipList -Workspace $ws
        if ($remote) {
            foreach ($r in $remote) {
                Import-BitbucketSnip -Id $r.Id -Workspace $ws -Force:$Force
            }
        }
    }

    if ($Direction -in 'Push','Both') {
        script:Out-Info 'Pushing local snippets to Bitbucket…'
        $idx = script:LoadIdx
        foreach ($snipName in $idx.snippets.Keys) {
            $entry = $idx.snippets[$snipName]
            $hasBbId = $null -ne $entry.PSObject.Properties['BitbucketId'] -and $entry.BitbucketId
            if (-not $hasBbId) {
                Export-BitbucketSnip -Name $snipName
            }
        }
    }

    script:Out-OK 'Bitbucket sync complete.'
}

