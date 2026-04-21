# PSSnips — GitHub Gist integration.
# Functions that interact with the GitHub Gist API.
# All API calls require a GitHub personal access token with the 'gist' scope,
# set via Set-SnipConfig -GitHubToken or the $env:GITHUB_TOKEN environment variable.

function Get-GistList {
    <#
    .SYNOPSIS
        Lists GitHub Gists for the authenticated user or a specified GitHub username.

    .DESCRIPTION
        Calls the GitHub Gists API to retrieve a list of Gists and displays them in a
        formatted table showing the Gist ID, description, and file names. The number
        of results is controlled by -Count (default 30, max 100 per API call). Use
        -Filter to restrict results to Gists whose description or file names contain
        the given substring. Returns the raw API response objects for pipeline use.

    .PARAMETER Filter
        Optional. A substring to match against Gist descriptions and file names.
        Case-insensitive.

    .PARAMETER Count
        Optional. Maximum number of Gists to retrieve per API request. Default: 30.

    .PARAMETER Username
        Optional. Retrieve Gists for a different GitHub user. When omitted, defaults
        to the configured GitHubUsername, or the authenticated user's Gists.

    .EXAMPLE
        Get-GistList

        Lists the 30 most recent Gists for the configured user.

    .EXAMPLE
        Get-GistList -Filter 'deploy' -Count 50

        Lists up to 50 Gists whose description or file name contains 'deploy'.

    .EXAMPLE
        Get-GistList -Username octocat

        Lists public Gists for the GitHub user 'octocat'.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Object[]
        Returns the deserialized Gist API response objects. Each object contains id,
        description, html_url, files, and other GitHub API fields.

    .NOTES
        Requires a GitHub PAT with the 'gist' scope.
        Set via: Set-SnipConfig -GitHubToken 'ghp_...'  or  $env:GITHUB_TOKEN
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Filter   = '',
        [uint32]$Count    = 30,
        [string]$Username = ''
    )
    script:InitEnv
    $cfg  = script:LoadCfg
    $user = if ($Username) { $Username } elseif ($cfg.GitHubUsername) { $cfg.GitHubUsername } else { '' }
    $p    = [GitHubProvider]::new((script:GetGitHubToken), $user)
    try {
        $gists = @($p.ListRemote($Filter))
    } catch { Write-Error "GitHub API error: $_" -ErrorAction Continue; return }
    if ([int]$Count -lt $gists.Count) { $gists = $gists[0..([int]$Count - 1)] }

    if (-not $gists) { script:Out-Info "No gists found."; return }

    Write-Host ""
    Write-Host ("  {0,-34} {1,-38} {2}" -f 'GIST ID','DESCRIPTION','FILES') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 86)" -ForegroundColor DarkGray
    foreach ($g in $gists) {
        $files = ($g.files.PSObject.Properties.Name) -join ', '
        if ($files.Length -gt 30) { $files = $files.Substring(0,27) + '...' }
        $desc  = if ($g.description) { $g.description } else { '(no description)' }
        if ($desc.Length -gt 36) { $desc = $desc.Substring(0,33) + '...' }
        Write-Host ("  {0,-34} " -f $g.id) -ForegroundColor DarkYellow -NoNewline
        Write-Host ("{0,-38} {1}" -f $desc, $files) -ForegroundColor Gray
    }
    Write-Host ""
    return $gists
}

function Get-Gist {
    <#
    .SYNOPSIS
        Displays the full content of a GitHub Gist including all its files.

    .DESCRIPTION
        Fetches a specific Gist from the GitHub API by ID and prints each file's
        content to the terminal with syntax-coloured headers. If a file is marked
        truncated in the API response, the raw_url is fetched separately to retrieve
        the full content. Returns the raw Gist API object for pipeline use.

    .PARAMETER GistId
        Mandatory. The GitHub Gist ID (32-character hex string) to retrieve.

    .EXAMPLE
        Get-Gist abc123def456abc123def456abc1234567

        Fetches and displays all files in the specified Gist.

    .EXAMPLE
        $gist = Get-Gist abc123def456abc123def456abc1234567
        $gist.html_url

        Retrieves the Gist object and accesses its HTML URL.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Object
        Returns the deserialized Gist object from the GitHub API containing id,
        description, html_url, files, owner, and related metadata.

    .NOTES
        Requires a GitHub PAT with the 'gist' scope.
        Truncated file content (>1 MB) is fetched via an additional web request
        to the file's raw_url.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'GitHub Gist ID')]
        [ValidateNotNullOrEmpty()]
        [string]$GistId)
    $p = script:Get-RemoteProvider -Name 'GitHub'
    try { $gist = $p.GetRemoteById($GistId) }
    catch { Write-Error "Failed to fetch gist: $_" -ErrorAction Continue; return }

    Write-Host ""
    Write-Host "  Gist: $GistId" -ForegroundColor Cyan
    if ($gist.description) { Write-Host "  $($gist.description)" -ForegroundColor Gray }
    Write-Host "  $($gist.html_url)" -ForegroundColor DarkCyan
    Write-Host ""

    foreach ($fn in $gist.files.PSObject.Properties.Name) {
        $f   = $gist.files.$fn
        $ext = [System.IO.Path]::GetExtension($fn).TrimStart('.')
        $c   = script:LangColor -ext $ext
        Write-Host "  ── $fn ──" -ForegroundColor $c
        $body = if ($f.truncated) { (Invoke-RestMethod -Uri $f.raw_url).ToString() } else { $f.content }
        Write-Host $body
        Write-Host ""
    }
    return $gist
}

function Import-Gist {
    <#
    .SYNOPSIS
        Downloads a GitHub Gist and saves it as one or more local snippets.

    .DESCRIPTION
        Fetches the specified Gist from GitHub and writes each selected file to the
        configured SnippetsDir. The snippet language is inferred from the file
        extension. Multi-file Gists prompt interactively for which file to import
        unless -All is specified. If a snippet with the derived name already exists,
        a numeric suffix is appended to avoid collision (unless -Force is used).
        The Gist ID and URL are stored in the snippet's index metadata to enable
        future sync operations.

    .PARAMETER GistId
        Mandatory. The GitHub Gist ID to import.

    .PARAMETER Name
        Optional. Override the local snippet name. Only applies when importing a
        single file; ignored when -All is used.

    .PARAMETER FileName
        Optional. Imports only the specified file from a multi-file Gist.

    .PARAMETER All
        Optional switch. Imports all files from the Gist as separate snippets.

    .PARAMETER Force
        Optional switch. Overwrites existing snippets with the same name.

    .EXAMPLE
        Import-Gist abc123def456abc123def456abc1234567

        Imports the first (or only) file from the Gist as a local snippet.

    .EXAMPLE
        Import-Gist abc123def456abc123def456abc1234567 -Name my-local-name

        Imports the Gist and saves it with the local name 'my-local-name'.

    .EXAMPLE
        Import-Gist abc123def456abc123def456abc1234567 -All

        Imports every file in the Gist as individual snippets.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message per imported snippet.

    .NOTES
        When -Name is not supplied, the snippet name is derived from the Gist
        file name (without extension). For multi-file imports with -All, each file
        is stored using its original file base name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'GitHub Gist ID to import')]
        [ValidateNotNullOrEmpty()]
        [string]$GistId,
        [string]$Name      = '',
        [string]$FileName  = '',
        [switch]$All,
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg
    $p   = script:Get-RemoteProvider -Name 'GitHub'
    try { $gist = $p.GetRemoteById($GistId) }
    catch { Write-Error "Failed to fetch gist: $_" -ErrorAction Continue; return }

    $fileNames = @($gist.files.PSObject.Properties.Name)

    # Multi-file prompt when needed
    if ($fileNames.Count -gt 1 -and -not $All -and -not $FileName) {
        Write-Host "`n  Gist has $($fileNames.Count) files:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $fileNames.Count; $i++) { Write-Host "    [$i] $($fileNames[$i])" -ForegroundColor Gray }
        $choice = Read-Host "`n  File number to import (or 'all')"
        if ($choice -eq 'all') { $All = $true } else { $FileName = $fileNames[[int]$choice] }
    }

    $toImport = if ($All) { $fileNames } elseif ($FileName) { @($FileName) } else { @($fileNames[0]) }
    $idx = script:LoadIdx

    foreach ($fn in $toImport) {
        $f        = $gist.files.$fn
        $ext      = [System.IO.Path]::GetExtension($fn).TrimStart('.')
        $snipName = if ($Name -and $toImport.Count -eq 1) { $Name } else { [System.IO.Path]::GetFileNameWithoutExtension($fn) }

        # Deduplicate name
        if ($idx.snippets.ContainsKey($snipName) -and -not $Force) {
            $base = $snipName; $n = 1
            while ($idx.snippets.ContainsKey($snipName)) { $snipName = "$base-$n"; $n++ }
        }

        $body = if ($f.truncated) { (Invoke-RestMethod -Uri $f.raw_url).ToString() } else { $f.content }
        Set-Content (Join-Path $cfg.SnippetsDir "$snipName.$ext") -Value $body -Encoding UTF8

        $importMeta = [SnippetMetadata]::new()
        $importMeta.Name        = $snipName
        $importMeta.Description = if ($gist.description) { $gist.description } else { '' }
        $importMeta.Language    = $ext
        $importMeta.GistId      = $GistId
        $importMeta.GistUrl     = if ($gist.html_url) { $gist.html_url } else { '' }
        $idx.snippets[$snipName] = $importMeta
        script:Out-OK "Imported '$snipName' ($ext)."
        script:Write-AuditLog -Operation 'Import' -SnippetName $snipName
    }
    script:SaveIdx -Idx $idx
}

function Export-Gist {
    <#
    .SYNOPSIS
        Exports a local snippet to GitHub as a new or updated Gist.

    .DESCRIPTION
        Reads the snippet file and its metadata, then creates a new GitHub Gist via
        POST or updates the existing linked Gist via PATCH. The decision is based on
        whether the snippet's 'gistId' field in the index is set. After a successful
        API call, the Gist ID and URL are written back to index.json so that future
        calls update the same Gist. New Gists are secret by default; use -Public to
        create a publicly visible Gist.

    .PARAMETER Name
        Mandatory. The name of the local snippet to export.

    .PARAMETER Description
        Optional. A description for the Gist. Falls back to the snippet's description,
        then the snippet name if not provided.

    .PARAMETER Public
        Optional switch. Creates a public Gist. Default is a secret Gist.

    .EXAMPLE
        Export-Gist my-snippet

        Creates a secret Gist from 'my-snippet' or updates the linked one.

    .EXAMPLE
        Export-Gist my-snippet -Description 'Handy deploy script' -Public

        Creates or updates a public Gist with a specific description.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes the resulting Gist URL to the host on success.

    .NOTES
        Requires a GitHub PAT with the 'gist' scope.
        If the snippet has a gistId in the index, the Gist is updated (PATCH).
        If not, a new Gist is created (POST) and the ID is saved to the index.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to export as a Gist')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Description = '',
        [switch]$Public
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $meta    = $idx.snippets[$Name]
    $path    = script:FindFile -Name $Name
    $content = Get-Content $path -Raw -Encoding UTF8
    $fn      = "$Name.$($meta.Language)"
    $desc    = if ($Description) { $Description } elseif ($meta.Description) { $meta.Description } else { $Name }

    $p = script:Get-RemoteProvider -Name 'GitHub'
    if (-not $p.IsConfigured()) { Write-Error "GitHub credentials not configured. Run Set-SnipConfig -GitHubToken <token>." -ErrorAction Continue; return }
    try {
        if ($meta.GistId) {
            $p.UpdateRemote($meta.GistId, $fn, $content)
            $gistUrl = if ($meta.GistUrl) { $meta.GistUrl } else { '' }
        } else {
            $result  = $p.CreateRemote($desc, $content, $meta.Language, -not $Public)
            $idx.snippets[$Name].GistId  = $result.Id
            $idx.snippets[$Name].GistUrl = $result.Url
            script:SaveIdx -Idx $idx
            $gistUrl = $result.Url
        }
        script:Out-OK "Gist $(if ($meta.GistId) {'updated'} else {'created'}): $gistUrl"
        script:Write-AuditLog -Operation 'Export' -SnippetName $Name
        script:Invoke-SnipEvent -EventName 'SnipPublished' -Data @{
            Name     = $Name
            Provider = 'github'
            Url      = $gistUrl
        }
    } catch { Write-Error "Failed to export gist: $_" -ErrorAction Continue }
}

function Invoke-Gist {
    <#
    .SYNOPSIS
        Downloads and executes a GitHub Gist file without saving it locally.

    .DESCRIPTION
        Fetches a Gist from GitHub, writes the selected file to a temporary path in
        $env:TEMP, executes it with the appropriate language runner, and then deletes
        the temporary file in a finally block. The runner selection follows the same
        logic as Invoke-Snip (ps1, py, js, bat/cmd, sh, rb, go). Supports -WhatIf
        via ShouldProcess — with -WhatIf the file is not written or executed.
        When the Gist has multiple files, the first file matching a known runnable
        extension is selected automatically; use -FileName to specify explicitly.

    .PARAMETER GistId
        Mandatory. The GitHub Gist ID to fetch and run.

    .PARAMETER FileName
        Optional. The specific file within the Gist to run. When omitted, the first
        file with a known runnable extension is selected.

    .PARAMETER ArgumentList
        Optional. Arguments forwarded to the language runner after the file path.

    .EXAMPLE
        Invoke-Gist abc123def456abc123def456abc1234567

        Fetches and executes the runnable file in the specified Gist.

    .EXAMPLE
        Invoke-Gist abc123def456abc123def456abc1234567 -FileName script.ps1

        Runs the named file from the Gist.

    .EXAMPLE
        Invoke-Gist abc123def456abc123def456abc1234567 -WhatIf

        Shows what would be executed without actually running it.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Variable. Output depends on the language runner.

    .NOTES
        The temporary file is always deleted after execution (or on error) via a
        try/finally block. The temp file is placed in $env:TEMP with a random name.
        Requires a GitHub PAT with the 'gist' scope.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'GitHub Gist ID to run')]
        [ValidateNotNullOrEmpty()]
        [string]$GistId,
        [string]  $FileName    = '',
        [string[]]$ArgumentList = @()
    )
    $p = script:Get-RemoteProvider -Name 'GitHub'
    try { $gist = $p.GetRemoteById($GistId) }
    catch { Write-Error "Failed to fetch gist: $_" -ErrorAction Continue; return }

    $fileNames = @($gist.files.PSObject.Properties.Name)
    $target = if ($FileName) { $FileName }
              elseif ($fileNames.Count -eq 1) { $fileNames[0] }
              else { $fileNames | Where-Object { $_ -match '\.(ps1|py|js|bat|cmd|sh|rb|go)$' } | Select-Object -First 1 }

    if (-not $target) { Write-Error "Cannot determine runnable file. Use -FileName." -ErrorAction Continue; return }

    $f    = $gist.files.$target
    $ext  = [System.IO.Path]::GetExtension($target).TrimStart('.').ToLower()
    $body = if ($f.truncated) { (Invoke-RestMethod -Uri $f.raw_url).ToString() } else { $f.content }

    script:Out-Info "Running gist $GistId → $target"

    if ($PSCmdlet.ShouldProcess($target, "Execute gist file")) {
        $tmp = Join-Path $env:TEMP "pssnips_$([System.IO.Path]::GetRandomFileName()).$ext"
        try {
            Set-Content $tmp -Value $body -Encoding UTF8 -ErrorAction Stop
            # Template variable substitution
            $gistPhMatches = [regex]::Matches($body, '\{\{([A-Z0-9_]+)(?::([^}]*))?\}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $gistPlaceholders = @($gistPhMatches | ForEach-Object { $_.Groups[1].Value.ToUpper() } | Select-Object -Unique)
            $gistPhDefaults = @{}
            foreach ($m in $gistPhMatches) {
                $phName = $m.Groups[1].Value.ToUpper()
                if ($m.Groups[2].Success -and -not $gistPhDefaults.ContainsKey($phName)) {
                    $gistPhDefaults[$phName] = $m.Groups[2].Value
                }
            }
            if ($gistPlaceholders.Count -gt 0) {
                $gistVarContent = Get-Content $tmp -Raw -Encoding UTF8
                foreach ($ph in $gistPlaceholders) {
                    $envVal = (Get-Item "env:$ph" -ErrorAction SilentlyContinue).Value
                    if ($envVal) {
                        $val = $envVal
                    } elseif ($gistPhDefaults.ContainsKey($ph) -and $gistPhDefaults[$ph] -ne '') {
                        $default = $gistPhDefaults[$ph]
                        $userInput = Read-Host "  Value for {{$ph}} [$default]"
                        $val = if ($userInput -ne '') { $userInput } else { $default }
                    } else {
                        $val = Read-Host "  Value for {{$ph}}"
                    }
                    $gistVarContent = $gistVarContent -replace "\{\{$ph(?::[^}]*)?\}\}", $val
                }
                Set-Content $tmp -Value $gistVarContent -Encoding UTF8
            }
            switch ($ext) {
                { $_ -in 'ps1','psm1' }  { & $tmp @ArgumentList }
                'py'  { $py = @('python','python3') | Where-Object { Get-Command $_ -EA 0 } | Select-Object -First 1; if ($py) { & $py $tmp @ArgumentList } }
                'js'  { if (Get-Command node -EA 0) { & node $tmp @ArgumentList } }
                { $_ -in 'bat','cmd' }   { & cmd /c $tmp @ArgumentList }
                'sh'  { if (Get-Command bash -EA 0) { & bash $tmp @ArgumentList } else { & wsl bash $tmp @ArgumentList } }
                'rb'  { if (Get-Command ruby -EA 0) { & ruby $tmp @ArgumentList } }
                'go'  { if (Get-Command go   -EA 0) { & go run $tmp @ArgumentList } }
                default { script:Out-Warn "No runner for '.$ext'. Saved to: $tmp"; return }
            }
        } finally {
            if (Test-Path $tmp) { Remove-Item $tmp -Force -EA SilentlyContinue }
        }
    }
}

function Sync-Gist {
    <#
    .SYNOPSIS
        Synchronises a local snippet with its linked GitHub Gist (pull or push).

    .DESCRIPTION
        Bi-directional sync between a local snippet and the GitHub Gist it was
        linked to via Export-Gist or Import-Gist. By default (pull mode) the local
        snippet file is overwritten with the latest content from GitHub. With -Push,
        the local file's current content is uploaded to GitHub, updating the Gist.
        The snippet must already have a linked gistId; run Export-Gist first to
        establish the link.

    .PARAMETER Name
        Mandatory. The name of the local snippet to synchronise.

    .PARAMETER Push
        Optional switch. Pushes the local snippet content to GitHub (update Gist).
        Without this switch, the default is to pull (download from GitHub).

    .EXAMPLE
        Sync-Gist my-snippet

        Pulls the latest Gist content from GitHub into the local snippet file.

    .EXAMPLE
        Sync-Gist my-snippet -Push

        Uploads the current local snippet content to the linked GitHub Gist.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a status message to the host.

    .NOTES
        Pull mode calls Import-Gist -Force which overwrites the local file.
        Push mode calls Export-Gist which PATCHes the existing Gist.
        The snippet must have a non-null gistId in the index. If not, an error
        is displayed directing the user to run Export-Gist first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to sync with its Gist')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Push
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }
    if (-not $idx.snippets[$Name].GistId)      { Write-Error "'$Name' has no linked gist. Run Export-Gist first." -ErrorAction Continue; return }
    if ($Push) { Export-Gist -Name $Name }
    else       { Import-Gist -GistId $idx.snippets[$Name].GistId -Name $Name -Force }
}

