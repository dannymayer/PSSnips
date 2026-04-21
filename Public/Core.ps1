# PSSnips — Core snippet CRUD: Get-Snip, New-Snip, Remove-Snip, Edit-Snip, etc.
# Create, read, update, and delete operations for local snippet files.
# Each function maintains both the snippet file on disk and the index.json metadata.

function Get-Snip {
    <#
    .SYNOPSIS
        Lists local snippets with optional filtering by name, description, tag, language, or content.

    .DESCRIPTION
        Reads the snippet index (index.json) and outputs a formatted table of all
        matching snippets. Filtering is case-insensitive and matches against the
        snippet name, its description, and its tags when -Filter is used. When
        -Content is also specified the body of each snippet file is searched as well.
        Use -Tag for an exact tag match or -Language to restrict by file extension.
        Use -SortBy to control ordering: Name (default, ascending), Modified
        (ascending), RunCount (descending), or LastRun (descending). Pinned snippets
        always float to the top of the list regardless of -SortBy. Returns an array
        of PSCustomObject rows so results can be piped to other commands.

    .PARAMETER Filter
        Optional. A wildcard substring matched against the snippet name, description,
        and tags. Accepts partial strings (e.g., 'azure' matches 'azure-deploy').
        When combined with -Content, the snippet file body is also searched.

    .PARAMETER Tag
        Optional. An exact tag value to filter by. The snippet must have this tag
        in its tags array to be included in the results.

    .PARAMETER Language
        Optional. A file extension (without the dot) to restrict results to a single
        language (e.g., 'py', 'ps1', 'js').

    .PARAMETER Content
        Optional switch. When specified together with -Filter, the body of each
        snippet file is also searched for the filter string (case-insensitive).
        Files that cannot be read are silently skipped.

    .PARAMETER SortBy
        Optional. Controls the sort order of the output. Accepted values:
          Name      – alphabetical ascending (default)
          Modified  – last-modified timestamp ascending
          RunCount  – most-run snippets first (descending)
          LastRun   – most-recently run snippets first (descending)
        Pinned snippets always appear before non-pinned ones.

    .EXAMPLE
        Get-Snip

        Lists all snippets in the index, sorted by name.

    .EXAMPLE
        Get-Snip -Filter azure

        Lists all snippets whose name, description, or tags contain 'azure'.

    .EXAMPLE
        Get-Snip -Filter azure -Content

        Lists all snippets whose name, description, tags, OR file body contains 'azure'.

    .EXAMPLE
        Get-Snip -Tag devops -Language ps1

        Lists PowerShell snippets tagged 'devops'.

    .EXAMPLE
        Get-Snip -SortBy RunCount

        Lists all snippets ordered by run frequency (most-run first).

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        PSSnips.SnippetInfo
        Returns typed [PSSnips.SnippetInfo] objects with the following properties:
          Name         [string]   – snippet key/filename stem
          Language     [string]   – file extension (e.g. ps1, py, js)
          Lang         [string]   – alias for Language (backwards compatibility)
          Gist         [string]   – 'linked', '[shared]', or ''
          GistUrl      [string]   – full GitHub Gist URL when linked, else ''
          Source       [string]   – 'local' or '[shared]'
          Tags         [string]   – comma-joined tag list for display
          TagList      [string[]] – individual tags array (use -contains for filtering)
          Modified     [string]   – formatted date string (yyyy-MM-dd)
          ModifiedDate [datetime] – typed datetime for sorting/filtering, or $null
          Desc         [string]   – description
          Description  [string]   – alias for Desc (for discoverability)
          Runs         [int]      – run count
          Pinned       [bool]     – whether snippet is pinned
          ContentHash  [string]   – SHA hash of snippet content from index

        Returns nothing (displays an info message) when no snippets match.

    .NOTES
        The @($m.tags) wrapping inside the filter logic normalises tags to an array
        even when the JSON deserializer returns a bare string for a single-element
        array (a known PowerShell 5.1 ConvertFrom-Json quirk).
        Run history fields (runCount, lastRun) are written to the index by Invoke-Snip.
        The PSTypeName 'PSSnips.SnippetInfo' activates the TableControl view defined
        in PSSnips.Format.ps1xml, replacing the old Write-Host table output.
    #>
    [CmdletBinding()]
    [OutputType('PSSnips.SnippetInfo')]
    param(
        [Parameter(Position=0)][string]$Filter   = '',
        [string]$Tag      = '',
        [string]$Language = '',
        [switch]$Content,   # when set, also search inside snippet file bodies
        [ValidateSet('Name','Modified','RunCount','LastRun')]
        [string]$SortBy = 'Name',
        [switch]$Shared,
        [Parameter(ParameterSetName='List')]
        [string]$Author = ''
    )
    script:InitEnv
    $idx = if ($Shared) {
        $sharedDir = script:GetSharedDir
        if (-not $sharedDir) { return }
        $sharedIdxFile = Join-Path $sharedDir 'shared-index.json'
        if (-not (Test-Path $sharedIdxFile)) {
            script:Out-Info "No shared-index.json found at $sharedDir."
            return
        }
        try {
            $raw = Get-Content $sharedIdxFile -Raw -Encoding UTF8 -ErrorAction Stop
            if ($raw) {
                $si = $raw | ConvertFrom-Json -AsHashtable
                if (-not $si.ContainsKey('snippets')) { $si['snippets'] = @{} }
                foreach ($k in @($si.snippets.Keys)) {
                    if ($si.snippets[$k] -is [hashtable]) {
                        $si.snippets[$k] = [SnippetMetadata]::FromHashtable($si.snippets[$k])
                    }
                }
                $si
            } else { @{ snippets = @{} } }
        } catch { @{ snippets = @{} } }
    } else {
        script:LoadIdx
    }
    if ($idx.snippets.Count -eq 0) {
        script:Out-Info "No snippets yet. Use 'snip new <name>' to create one."
        return
    }

    # Phase 1: Filter — collect matching snippet names
    $matchedNames = [System.Collections.Generic.List[string]]::new()
    foreach ($name in $idx.snippets.Keys) {
        $m  = $idx.snippets[$name]
        # @($m.tags) normalises to array: PS 5.1 ConvertFrom-Json may return a bare
        # string for a single-element JSON array; wrapping with @() is defensive.
        $mf = -not $Filter   -or $name -like "*$Filter*" -or ($m.Description -like "*$Filter*") -or
              ((@($m.Tags) -join ',') -like "*$Filter*") -or
              ($Content -and $Filter -and (script:SearchSnipContent -Name $name -SearchString $Filter))
        $mt = -not $Tag      -or (@($m.Tags) -contains $Tag)
        $ml = -not $Language -or $m.Language -eq $Language
        if ($mf -and $mt -and $ml) { $matchedNames.Add($name) }
    }

    # Phase 2: Sort by $SortBy
    $sortedNames = switch ($SortBy) {
        'Modified' {
            $matchedNames | Sort-Object {
                $idx.snippets[$_].Modified
            }
        }
        'RunCount' {
            $matchedNames | Sort-Object {
                $idx.snippets[$_].RunCount
            } -Descending
        }
        'LastRun'  {
            $matchedNames | Sort-Object {
                $idx.snippets[$_].LastRun
            } -Descending
        }
        default    { $matchedNames | Sort-Object }   # 'Name' — alphabetical ascending
    }

    # Phase 3: Pinned entries float to the top of the listing
    $pinnedNames    = @($sortedNames | Where-Object {
        $idx.snippets[$_].Pinned -eq $true
    })
    $nonPinnedNames = @($sortedNames | Where-Object {
        $idx.snippets[$_].Pinned -ne $true
    })
    $finalNames = @($pinnedNames) + @($nonPinnedNames)

    # Phase 4: Build typed output objects
    $rows = @(foreach ($name in $finalNames) {
        $m            = $idx.snippets[$name]
        $pinned       = $m.Pinned -eq $true
        $runCount     = $m.RunCount
        $tagArray     = [string[]]@($m.Tags | Where-Object { $_ })
        $modifiedDate = if ($m.Modified) { $m.Modified } else { $null }
        $modifiedDisp = if ($modifiedDate) { $modifiedDate | Get-Date -Format 'yyyy-MM-dd' } else { '' }
        $gistDisplay  = if ($Shared) { '[shared]' } elseif ($m.GistId) { 'linked' } else { '' }
        $gistUrl      = if (-not $Shared -and $m.GistUrl) { $m.GistUrl } else { '' }
        $descValue    = if ($m.Description) { $m.Description } else { '' }
        $hashValue    = $m.ContentHash
        $sourceValue  = if ($Shared) { '[shared]' } else { 'local' }
        $authorValue  = $m.CreatedBy
        $obj = [pscustomobject]@{
            PSTypeName   = 'PSSnips.SnippetInfo'
            Name         = [string]$name
            Language     = [string]$m.Language
            Lang         = [string]$m.Language
            Gist         = [string]$gistDisplay
            GistUrl      = [string]$gistUrl
            Source       = [string]$sourceValue
            Tags         = [string]($tagArray -join ', ')
            TagList      = $tagArray
            Modified     = [string]$modifiedDisp
            ModifiedDate = $modifiedDate
            Desc         = [string]$descValue
            Description  = [string]$descValue
            Runs         = [int]$runCount
            Pinned       = [bool]$pinned
            ContentHash  = [string]$hashValue
            Author       = [string]$authorValue
        }
        $obj
    })

    if ($Author) { $rows = @($rows | Where-Object { $_.Author -like "*$Author*" }) }
    if (-not $rows) { script:Out-Info "No snippets match that filter."; return }
    return $rows
}

function Show-Snip {
    <#
    .SYNOPSIS
        Displays the content of a named snippet in the terminal.

    .DESCRIPTION
        Reads the snippet file from disk and writes its content to the terminal.
        By default, a decorative header showing the snippet name, description, and
        Gist URL (if linked) is printed before the content. Use -Raw to suppress
        the header and print only the raw file contents. Use -PassThru to return the
        content as a string for use in scripts or pipelines instead of printing it.

    .PARAMETER Name
        Mandatory. The name of the snippet to display (without file extension).

    .PARAMETER Raw
        Optional switch. When specified, suppresses the decorative header and prints
        only the raw file content.

    .PARAMETER PassThru
        Optional switch. When specified, returns the snippet content as a string
        instead of writing to the host. The decorative header is not printed.

    .PARAMETER Comments
        Optional switch. When specified, displays user comments for the snippet
        below the content. Comments are read from ~/.pssnips/comments/<name>.json.
        Has no effect when -PassThru is specified. Use Add-SnipComment to add comments.

    .PARAMETER Highlighted
        Optional switch. When specified, applies ANSI syntax highlighting to PS1/PSM1/PSD1
        snippet content using the built-in PowerShell tokenizer. For non-PS files, falls
        back to plain output unless bat is also available. Has no effect when -PassThru
        is specified.

    .PARAMETER Format
        Optional. Controls the display format. Accepted values:
          Plain  – (default) raw file content with no syntax highlighting.
          Auto   – uses bat if available, otherwise falls back to the PS tokenizer for
                   PS files, or plain for all other file types.
          Bat    – always uses bat for highlighting; warns and falls back to plain if bat
                   is not installed.
        Has no effect when -PassThru is specified.

    .EXAMPLE
        Show-Snip my-snippet

        Displays the snippet content with a decorative header.

    .EXAMPLE
        Show-Snip my-snippet -PassThru | Set-Clipboard

        Returns the snippet content as a string and copies it to the clipboard.

    .EXAMPLE
        Show-Snip my-snippet -Raw

        Prints the raw file content without any header decoration.

    .EXAMPLE
        Show-Snip my-deploy -Highlighted

        Displays a PowerShell snippet with ANSI syntax highlighting via the PS tokenizer.

    .EXAMPLE
        Show-Snip my-deploy -Format Auto

        Displays with bat if installed, otherwise falls back to PS tokenizer highlighting.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String
        Only when -PassThru is specified. Returns the full file content as a string.
        Otherwise outputs nothing (writes directly to the host).

    .NOTES
        If the snippet name is not found in the file system, an error message is
        displayed and the function returns without throwing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the local snippet')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Raw,
        [switch]$PassThru,
        [switch]$Comments,
        [Parameter()]
        [switch]$Highlighted,
        [Parameter()]
        [ValidateSet('Auto', 'Bat', 'Plain')]
        [string]$Format = 'Plain'
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $content = Get-Content $path -Raw -Encoding UTF8
    if ($PassThru) { return $content }

    if (-not $Raw) {
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($Name)) {
            $m = $idx.snippets[$Name]; $c = script:LangColor -ext $m.Language
            Write-Host ""
            Write-Host ("  ╔═ {0}" -f $Name) -ForegroundColor $c -NoNewline
            if ($m.Description) { Write-Host (" – {0}" -f $m.Description) -ForegroundColor DarkGray -NoNewline }
            Write-Host " ═╗" -ForegroundColor $c
            if ($m.GistUrl) { Write-Host "  │ Gist: $($m.GistUrl)" -ForegroundColor DarkCyan }
            Write-Host ""
        }
    }

    $displayContent = $content
    if ($Highlighted -or $Format -eq 'Auto' -or $Format -eq 'Bat') {
        $ext         = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
        $isPsFile    = $ext -eq 'ps1' -or $ext -eq 'psm1' -or $ext -eq 'psd1'
        $batAvail    = $null -ne (Get-Command bat -ErrorAction SilentlyContinue)
        if ($isPsFile) {
            if ($Format -eq 'Bat' -or ($Format -eq 'Auto' -and $batAvail)) {
                $displayContent = script:Invoke-BatHighlight -Code $content -Extension $ext
            } elseif ($Highlighted -or $Format -eq 'Auto') {
                $displayContent = script:ConvertTo-HighlightedPS -Code $content
            }
        } elseif ($Format -eq 'Bat' -or ($Format -eq 'Auto' -and $batAvail)) {
            $displayContent = script:Invoke-BatHighlight -Code $content -Extension $ext
        }
    }
    Write-Host $displayContent

    if ($Comments -and -not $PassThru) {
        $commentsDir  = Join-Path $script:Home 'comments'
        $commentsFile = Join-Path $commentsDir "$Name.json"
        if (Test-Path $commentsFile) {
            try {
                $commentList = @(Get-Content $commentsFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json)
                if ($commentList.Count -gt 0) {
                    Write-Host '  ── Comments ──' -ForegroundColor DarkCyan
                    foreach ($cm in $commentList) {
                        $ts = try { [datetime]$cm.timestamp | Get-Date -Format 'yyyy-MM-dd HH:mm' } catch { $cm.timestamp }
                        Write-Host ("  [{0}] {1}: {2}" -f $ts, $cm.author, $cm.text) -ForegroundColor Gray
                    }
                    Write-Host ''
                }
            } catch { Write-Verbose "Failed to read comments for '$Name': $($_.Exception.Message)" }
        }
    }

    if (-not $Raw) { Write-Host "" }
}

function New-Snip {
    <#
    .SYNOPSIS
        Creates a new snippet file and opens it in the configured editor.

    .DESCRIPTION
        Creates a snippet file in the configured snippets directory, registers it in
        the index (index.json), and opens the file in the editor unless -Content is
        provided. When -Content is supplied the file is written with that content and
        the editor is not launched. When no -Content is given, a language-appropriate
        template is written first. If a snippet with the same name already exists the
        function warns and returns without overwriting.

    .PARAMETER Name
        Mandatory. A short identifier for the snippet (no spaces, no extension).
        Used as both the file base name and the index key.

    .PARAMETER Language
        Optional. The file extension (without dot) that determines the snippet's
        language and runner (e.g., 'ps1', 'py', 'js', 'bat', 'sh', 'rb', 'go').
        Defaults to the configured DefaultLanguage (ps1 out of the box).

    .PARAMETER Description
        Optional. A short human-readable description stored in the index and
        shown in Get-Snip listings.

    .PARAMETER Tags
        Optional. An array of tag strings to categorise the snippet
        (e.g., @('devops', 'azure')).

    .PARAMETER Content
        Optional. If provided, this string is written directly to the snippet file
        and the editor is not launched. Useful for programmatic creation.

    .PARAMETER Editor
        Optional. Overrides the configured editor for this single invocation
        (e.g., 'code' to open in VS Code).

    .EXAMPLE
        New-Snip deploy-script -Language ps1 -Description 'Azure deployment'

        Creates a new PowerShell snippet and opens it in the default editor.

    .EXAMPLE
        New-Snip parser -Language py -Tags @('data', 'util')

        Creates a Python snippet tagged 'data' and 'util'.

    .EXAMPLE
        New-Snip hello -Content 'Write-Host "Hello, World!"'

        Creates a snippet with pre-filled content without opening an editor.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success or warning message to the host.

    .NOTES
        Template files for ps1, py, js, ts, bat, sh, rb, and go are automatically
        populated with the snippet name and description as header comments.
        The editor is determined by script:GetEditor which walks the configured
        Editor then EditorFallbacks list.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the new snippet')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Position=1)][string]$Language = '',
        [string]$Description = '',
        [string[]]$Tags      = @(),
        [string]$Content     = '',
        [string]$Editor      = '',
        [switch]$Force,
        [switch]$IgnoreDuplicate
    )
    script:InitEnv
    $cfg = script:LoadCfg
    $idx = script:LoadIdx
    if ($idx.snippets.ContainsKey($Name)) {
        if (-not $Force -or -not $Content) {
            script:Out-Warn "Snippet '$Name' already exists. Use 'snip edit $Name' to modify it."; return
        }
        # Overwriting with -Force -Content: version existing content first
        $existingPath = script:FindFile -Name $Name
        if ($existingPath -and (Test-Path $existingPath)) {
            script:SaveVersion -Name $Name -FilePath $existingPath
        }
    }
    if (-not $Language) { $Language = $cfg.DefaultLanguage }
    $langExt = $Language.TrimStart('.').ToLower()

    $filePath     = Join-Path $cfg.SnippetsDir "$Name.$langExt"
    $finalContent = if ($Content) {
        $Content
    } else {
        if ($script:Templates.ContainsKey($langExt)) {
            $script:Templates[$langExt] -replace '\{name\}',$Name -replace '\{desc\}',$Description
        } else { "" }
    }

    # Duplicate content detection
    $newHash = script:GetContentHash -Content $finalContent
    if (-not $IgnoreDuplicate) {
        $dupEntry = $idx.snippets.Keys | Where-Object {
            $_ -ne $Name -and $idx.snippets[$_].ContentHash -eq $newHash
        } | Select-Object -First 1
        if ($dupEntry) {
            script:Out-Warn "Duplicate: content is identical to existing snippet '$dupEntry'."
            script:Out-Info "Use -IgnoreDuplicate to save anyway."
            return
        }
    }

    Set-Content $filePath -Value $finalContent -Encoding UTF8

    $snipAuthor = if ($env:USERNAME) { $env:USERNAME } else { 'unknown' }
    $newMeta = [SnippetMetadata]::new()
    $newMeta.Name        = $Name
    $newMeta.Description = $Description
    $newMeta.Language    = $langExt
    $newMeta.Tags        = $Tags
    $newMeta.ContentHash = $newHash
    $newMeta.CreatedBy   = $snipAuthor
    $newMeta.UpdatedBy   = $snipAuthor
    $idx.snippets[$Name] = $newMeta
    script:SaveIdx -Idx $idx
    script:UpdateFts -Name $Name
    script:Out-OK "Snippet '$Name' ($langExt) created."
    script:Write-AuditLog -Operation 'Create' -SnippetName $Name
    script:Invoke-SnipEvent -EventName 'SnipCreated' -Data @{
        Name        = $Name
        Language    = $langExt
        Description = $Description
        Tags        = $Tags
    }

    if (-not $Content) { Edit-Snip -Name $Name -Editor $Editor }
}

function Add-Snip {
    <#
    .SYNOPSIS
        Adds a new snippet from an existing file or pipeline input.

    .DESCRIPTION
        Imports content into PSSnips from two sources:
          File     – reads a file from disk via -Path. The language is inferred from
                     the source file's extension when -Language is not specified.
          Pipeline – collects lines piped into the function and joins them with
                     newlines. Requires -Language when the extension cannot be
                     inferred from context.
        The snippet file is written to the configured SnippetsDir and registered in
        the index. Use -Force to overwrite an existing snippet with the same name.

    .PARAMETER Name
        Mandatory. The identifier for the new snippet (no spaces, no extension).

    .PARAMETER Path
        Optional (File parameter set). Path to the source file to import.
        The language is derived from the file extension when -Language is omitted.

    .PARAMETER InputObject
        Optional (Pipe parameter set). Accepts string lines from the pipeline.
        All lines are collected and joined before saving.

    .PARAMETER Language
        Optional. Overrides the inferred or default language/extension.

    .PARAMETER Description
        Optional. Short description stored in the index.

    .PARAMETER Tags
        Optional. Array of tag strings for the snippet.

    .PARAMETER Force
        Optional switch. Overwrites an existing snippet with the same name without
        prompting.

    .EXAMPLE
        Add-Snip my-script -Path .\deploy.ps1

        Imports deploy.ps1 as a snippet named 'my-script'.

    .EXAMPLE
        Get-Content .\parser.py | Add-Snip parser -Language py

        Pipes a Python file's contents into a new snippet named 'parser'.

    .INPUTS
        System.String[]
        Accepts string lines via the pipeline when using the Pipe parameter set.

    .OUTPUTS
        None. Writes a confirmation message to the host.

    .NOTES
        The Pipe parameter set collects all input in the process block and writes
        the snippet only in the end block after the pipeline has been fully read.
    #>
    [CmdletBinding(DefaultParameterSetName = 'File')]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name for the imported snippet')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(ParameterSetName='File', Position=1)][string]$Path,
        [Parameter(ParameterSetName='Pipe', ValueFromPipeline)][string[]]$InputObject,
        [string]$Language    = '',
        [string]$Description = '',
        [string[]]$Tags      = @(),
        [switch]$Force,
        [switch]$IgnoreDuplicate
    )
    begin   { $pipeContent = [System.Collections.Generic.List[string]]::new() }
    process { if ($PSCmdlet.ParameterSetName -eq 'Pipe' -and $InputObject) { $pipeContent.AddRange($InputObject) } }
    end {
        script:InitEnv
        $cfg = script:LoadCfg
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($Name) -and -not $Force) {
            script:Out-Warn "Snippet '$Name' already exists. Use -Force to overwrite."; return
        }
        $langHint = $Language
        $content = switch ($PSCmdlet.ParameterSetName) {
            'File' {
                if (-not $Path) { Write-Error "Specify -Path." -ErrorAction Continue; return }
                if (-not (Test-Path $Path)) { Write-Error "File not found: $Path" -ErrorAction Continue; return }
                if (-not $langHint) { $langHint = [System.IO.Path]::GetExtension($Path).TrimStart('.') }
                Get-Content $Path -Raw -Encoding UTF8
            }
            'Clipboard' { Get-Clipboard }
            'Pipe'      { $pipeContent -join "`n" }
        }
        if (-not $langHint) { $langHint = $cfg.DefaultLanguage }
        $langExt = $langHint.TrimStart('.').ToLower()
        $fp = Join-Path $cfg.SnippetsDir "$Name.$langExt"
        if ($idx.snippets.ContainsKey($Name) -and $Force) {
            script:SaveVersion -Name $Name -FilePath $fp
        }

        # Auto-extract CBH metadata from PowerShell files when no explicit values provided
        if ($langExt -in 'ps1','psm1' -and $content) {
            $cbh = script:ParseCBH -Content $content
            if (-not $Description -and $cbh.Synopsis) {
                $Description = $cbh.Synopsis
                script:Out-Info "Description from CBH .SYNOPSIS: $Description"
            }
            if ($Tags.Count -eq 0 -and $cbh.Tags.Count -gt 0) {
                $Tags = $cbh.Tags
                script:Out-Info "Tags from CBH .NOTES: $($Tags -join ', ')"
            }
        }

        # Duplicate content detection
        $addHash = script:GetContentHash -Content $content
        if (-not $IgnoreDuplicate) {
            $addDup = $idx.snippets.Keys | Where-Object {
                $_ -ne $Name -and $idx.snippets[$_].ContentHash -eq $addHash
            } | Select-Object -First 1
            if ($addDup) {
                script:Out-Warn "Duplicate: content is identical to existing snippet '$addDup'."
                script:Out-Info "Use -IgnoreDuplicate to save anyway."
                return
            }
        }

        Set-Content $fp -Value $content -Encoding UTF8
        $addAuthor = if ($env:USERNAME) { $env:USERNAME } else { 'unknown' }
        $addMeta = [SnippetMetadata]::new()
        $addMeta.Name        = $Name
        $addMeta.Description = $Description
        $addMeta.Language    = $langExt
        $addMeta.Tags        = $Tags
        $addMeta.ContentHash = $addHash
        $addMeta.CreatedBy   = $addAuthor
        $addMeta.UpdatedBy   = $addAuthor
        $idx.snippets[$Name] = $addMeta
        script:SaveIdx -Idx $idx
        script:UpdateFts -Name $Name
        script:Out-OK "Snippet '$Name' ($langExt, $($content.Length) chars) added."
    }
}

function Remove-Snip {
    <#
    .SYNOPSIS
        Deletes a local snippet file and removes its index entry.

    .DESCRIPTION
        Looks up the snippet by name in the index, optionally prompts for
        confirmation (based on the ConfirmDelete config setting or the -Force
        switch), deletes the snippet file from disk, and removes the metadata
        entry from index.json. If the snippet name is not found the function
        displays an error and returns without throwing.

    .PARAMETER Name
        Mandatory. The name of the snippet to delete.

    .PARAMETER Force
        Optional switch. Bypasses the interactive confirmation prompt regardless
        of the ConfirmDelete configuration setting.

    .EXAMPLE
        Remove-Snip old-script

        Deletes 'old-script', prompting for confirmation if ConfirmDelete is $true.

    .EXAMPLE
        Remove-Snip old-script -Force

        Deletes 'old-script' immediately without any confirmation prompt.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success or error message to the host.

    .NOTES
        The physical file and the index entry are both removed. This action is
        not reversible. Linked GitHub Gists are not affected.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to delete')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Force
    )
    script:InitEnv
    $cfg = script:LoadCfg
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    if (-not $Force -and $cfg.ConfirmDelete) {
        $yn = Read-Host "  Delete '$Name'? [y/N]"
        if ($yn -notin 'y','Y') { script:Out-Info "Cancelled."; return }
    }
    if ($Force -or $PSCmdlet.ShouldProcess($Name, 'Delete snippet')) {
        script:Write-AuditLog -Operation 'Delete' -SnippetName $Name
        script:Invoke-SnipEvent -EventName 'SnipDeleted' -Data @{ Name = $Name }
        $p = script:FindFile -Name $Name
        if ($p -and (Test-Path $p)) { Remove-Item $p -Force }
        $idx.snippets.Remove($Name)
        script:SaveIdx -Idx $idx
        script:RemoveFts -Name $Name
        script:Out-OK "Snippet '$Name' deleted."
    }
}

function Edit-Snip {
    <#
    .SYNOPSIS
        Opens a snippet file in the configured editor and updates its modified timestamp.

    .DESCRIPTION
        Resolves the snippet file path, launches the configured editor (or an override),
        and waits for the editor process to exit. After the editor closes, the snippet's
        'modified' timestamp in index.json is updated to the current UTC time.
        The editor resolution order is: -Editor override → configured Editor →
        EditorFallbacks list (nvim, code, notepad) → notepad as the final fallback.

    .PARAMETER Name
        Mandatory. The name of the snippet to edit.

    .PARAMETER Editor
        Optional. Overrides the configured editor for this invocation only.
        Must be a command resolvable on PATH (e.g., 'code', 'nvim', 'notepad').

    .EXAMPLE
        Edit-Snip my-snippet

        Opens 'my-snippet' in the default configured editor.

    .EXAMPLE
        Edit-Snip my-snippet -Editor code

        Opens 'my-snippet' in Visual Studio Code regardless of the configured editor.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. The editor runs synchronously; control returns after the editor exits.

    .NOTES
        The function calls script:GetEditor which walks the Editor and EditorFallbacks
        configuration keys. The @($cfg.Editor) wrapping ensures the Editor value is
        always iterated as an array even when stored as a bare string in the config.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to edit')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string]$Editor = ''
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    script:SaveVersion -Name $Name -FilePath $path
    $ed = script:GetEditor -Override $Editor
    script:Out-Info "Opening '$Name' in $ed ..."
    & $ed $path
    script:Write-AuditLog -Operation 'Edit' -SnippetName $Name
    script:Invoke-SnipEvent -EventName 'SnipEdited' -Data @{
        Name     = $Name
        FilePath = $path
    }

    # Touch the modified timestampand recompute content hash; auto-sync CBH for PS1 files
    $idx = script:LoadIdx
    if ($idx.snippets.ContainsKey($Name)) {
        $idx.snippets[$Name].Modified  = Get-Date
        $idx.snippets[$Name].UpdatedBy = if ($env:USERNAME) { $env:USERNAME } else { 'unknown' }
        if (Test-Path $path) {
            $editedContent = Get-Content $path -Raw -Encoding UTF8
            $idx.snippets[$Name].ContentHash = script:GetContentHash -Content $editedContent
            # Auto-fill empty description/tags from CBH for PowerShell snippets
            $ext = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
            if ($ext -in 'ps1','psm1') {
                $cbh = script:ParseCBH -Content $editedContent
                if ($cbh.Synopsis -and -not $idx.snippets[$Name].Description) {
                    $idx.snippets[$Name].Description = $cbh.Synopsis
                    script:Out-Info "Description synced from .SYNOPSIS: $($cbh.Synopsis)"
                }
                if ($cbh.Tags.Count -gt 0 -and @($idx.snippets[$Name].Tags).Count -eq 0) {
                    $idx.snippets[$Name].Tags = $cbh.Tags
                    script:Out-Info "Tags synced from .NOTES: $($cbh.Tags -join ', ')"
                }
            }
        }
        script:SaveIdx -Idx $idx
        script:UpdateFts -Name $Name
    }
}

function Invoke-Snip {
    <#
    .SYNOPSIS
        Executes a snippet or runs multiple snippets in sequence (pipeline/chain mode).

    .DESCRIPTION
        Single mode (-Name): resolves the snippet file, substitutes any {{PLACEHOLDER}}
        template variables in the content, then invokes the appropriate language runner.
        Runner selection: .ps1/.psm1 (dot-source), .py (python/python3), .js (node),
        .bat/.cmd (cmd /c), .sh (bash/wsl2/wsl), .rb (ruby), .go (go run),
        .sql (dbatools/SqlClient), other (Start-Process).

        Chain mode (-Pipeline): runs multiple snippets sequentially. Prints a header,
        executes each snippet by name in order, and prints a summary. By default stops
        on the first error unless -ContinueOnError is specified.

        After each single execution the snippet's runCount is incremented and lastRun
        is set in index.json. A failure to update run history never prevents output.

        PSRemoting (-ComputerName): for .ps1/.psm1 snippets, executes the snippet
        remotely on one or more computers via Invoke-Command. Requires WinRM/PSRemoting.

    .PARAMETER Name
        Mandatory (Single set). The name of the snippet to execute.

    .PARAMETER Pipeline
        Mandatory (Chain set). An array of snippet names to run in sequence.
        You may also pass a single comma-separated string which is split automatically.

    .PARAMETER ArgumentList
        Optional (Single set). Additional arguments forwarded to the language runner.

    .PARAMETER ContinueOnError
        Optional (Chain set). When set, pipeline execution continues even if a snippet
        in the chain fails. Without this switch, the pipeline stops at the first error.

    .PARAMETER Variables
        Optional (Single set). A hashtable of placeholder values used to fill
        {{VARIABLE_NAME}} placeholders in the snippet body without prompting.
        Keys must match placeholder names exactly (case-insensitive match supported).
        Any placeholder NOT found in this hashtable will be prompted interactively.

    .PARAMETER ComputerName
        Optional (Single set). One or more remote computer names. When provided, the
        snippet (must be .ps1 or .psm1) is executed remotely via Invoke-Command using
        PSRemoting/WinRM. Variable substitution is applied before remote execution.

    .PARAMETER Credential
        Optional (Single set). PSCredential for remote authentication when using
        -ComputerName. If omitted, the current user's credentials are used.

    .PARAMETER ConnectionString
        Optional (Single set). ADO.NET connection string for executing .sql snippets.
        Example: 'Server=.;Database=master;Integrated Security=True'
        If omitted when running a .sql snippet, a helpful error is shown.

    .EXAMPLE
        Invoke-Snip deploy-script

        Runs the 'deploy-script' snippet.

    .EXAMPLE
        Invoke-Snip my-py-script -ArgumentList '--verbose', '--dry-run'

        Runs a Python snippet and passes '--verbose --dry-run' to the interpreter.

    .EXAMPLE
        Invoke-Snip deploy -Variables @{ ENV = 'prod'; REGION = 'eastus' }

        Runs 'deploy' filling {{ENV}} and {{REGION}} without interactive prompts.

    .EXAMPLE
        Invoke-Snip -Pipeline 'setup','build','deploy'

        Runs three snippets in sequence. Stops on the first failure.

    .EXAMPLE
        Invoke-Snip -Pipeline 'setup','build','deploy' -ContinueOnError

        Runs all three snippets, reporting errors but not stopping.

    .EXAMPLE
        Invoke-Snip my-script -ComputerName 'server01','server02'

        Runs 'my-script.ps1' on server01 and server02 via PSRemoting.

    .EXAMPLE
        Invoke-Snip my-script -ComputerName 'server01' -Credential (Get-Credential)

        Runs 'my-script.ps1' remotely with explicit credentials.

    .EXAMPLE
        Invoke-Snip my-query -ConnectionString 'Server=.;Database=master;Integrated Security=True'

        Runs a .sql snippet against the specified SQL Server database.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Variable. Output depends on the language runner. PowerShell snippets can
        return objects to the pipeline; other runtimes write to stdout/stderr.

    .NOTES
        Template variables use the syntax {{VARIABLE_NAME}} (uppercase letters,
        digits, and underscores). Matching is case-insensitive for the -Variables
        hashtable lookup. If any substitutions are made, the snippet runs from a
        temporary file that is deleted in a finally block.
        For .sh snippets on Windows, WSL2 bash is preferred when available; path
        translation (C:\...) → /mnt/c/... is performed automatically. Falls back
        to native bash (Git Bash) then WSL1 bash.
        Run history (runCount, lastRun) is updated in index.json after execution.

        Supports -WhatIf (ShouldProcess). When -WhatIf is specified in Single mode,
        the snippet content (with placeholders resolved) is displayed and no execution
        or audit-log write occurs. Chain mode passes -WhatIf through to each recursive
        Invoke-Snip call automatically.
    #>
    [CmdletBinding(DefaultParameterSetName='Single', SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position=0, ParameterSetName='Single', HelpMessage='Name of the snippet to run')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName='Chain', HelpMessage='Array of snippet names to run in sequence')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Pipeline,

        [Parameter(Position=1, ValueFromRemainingArguments, ParameterSetName='Single')]
        [string[]]$ArgumentList = @(),

        [Parameter(ParameterSetName='Chain')]
        [switch]$ContinueOnError,

        [Parameter(ParameterSetName='Single')]
        [hashtable]$Variables = @{},

        [Parameter(ParameterSetName='Single')]
        [string[]]$ComputerName = @(),

        [Parameter(ParameterSetName='Single')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(ParameterSetName='Single')]
        [string]$ConnectionString = ''
    )

    # ── Chain / Pipeline mode ────────────────────────────────────────────────
    if ($PSCmdlet.ParameterSetName -eq 'Chain') {
        $names = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $Pipeline) {
            foreach ($part in ($entry -split ',')) {
                $trimmed = $part.Trim()
                if ($trimmed) { $names.Add($trimmed) }
            }
        }
        $arrow  = ' → '
        script:Out-Info ("Running pipeline: {0}" -f ($names -join $arrow))
        Write-Host ""

        $succeeded = 0
        $stopped   = $null
        for ($i = 0; $i -lt $names.Count; $i++) {
            $sn = $names[$i]
            $snipPath = script:FindFile -Name $sn
            if (-not $snipPath -or -not (Test-Path $snipPath)) {
                script:Out-Err "Pipeline snippet '$sn' not found."
                if (-not $ContinueOnError) {
                    $stopped = $sn
                    break
                }
                continue
            }
            try {
                Invoke-Snip -Name $sn
                $succeeded++
            } catch {
                script:Out-Err "Pipeline snippet '$sn' failed: $_"
                if (-not $ContinueOnError) {
                    $stopped = $sn
                    break
                }
            }
        }

        Write-Host ""
        if ($stopped) {
            script:Out-Warn ("Pipeline stopped at '{0}' ({1}/{2} ran)" -f $stopped, $i, $names.Count)
        } else {
            script:Out-OK ("Pipeline complete: {0}/{1} succeeded" -f $succeeded, $names.Count)
        }
        return
    }

    # ── Single mode ──────────────────────────────────────────────────────────
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $ext     = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
    $content = Get-Content $path -Raw -Encoding UTF8

    # Template variable substitution
    $phMatches = [regex]::Matches($content, '\{\{([A-Z0-9_]+)(?::([^}]*))?\}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $placeholders = @($phMatches | ForEach-Object { $_.Groups[1].Value.ToUpper() } | Select-Object -Unique)
    $phDefaults = @{}
    foreach ($m in $phMatches) {
        $phName = $m.Groups[1].Value.ToUpper()
        if ($m.Groups[2].Success -and -not $phDefaults.ContainsKey($phName)) {
            $phDefaults[$phName] = $m.Groups[2].Value
        }
    }

    $resolvedVars = @{}
    foreach ($k in $Variables.Keys) { $resolvedVars[$k.ToUpper()] = $Variables[$k] }

    foreach ($ph in $placeholders) {
        if (-not $resolvedVars.ContainsKey($ph)) {
            $envVal = (Get-Item "env:$ph" -ErrorAction SilentlyContinue).Value
            if ($envVal) {
                $resolvedVars[$ph] = $envVal
            } elseif ($phDefaults.ContainsKey($ph) -and $phDefaults[$ph] -ne '') {
                $default = $phDefaults[$ph]
                $userInput = Read-Host "  Value for {{$ph}} [$default]"
                $resolvedVars[$ph] = if ($userInput -ne '') { $userInput } else { $default }
            } else {
                $resolvedVars[$ph] = Read-Host "  Value for {{$ph}}"
            }
        }
    }

    $runPath = $path
    $tmpFile = $null
    if ($placeholders.Count -gt 0) {
        $substituted = $content
        foreach ($ph in $placeholders) {
            $substituted = $substituted -replace "\{\{$ph(?::[^}]*)?\}\}", $resolvedVars[$ph]
        }
        $tmpFile = Join-Path $env:TEMP "pssnips_var_$([System.IO.Path]::GetRandomFileName()).$ext"
        Set-Content $tmpFile -Value $substituted -Encoding UTF8
        $runPath = $tmpFile
    }

    if (-not $PSCmdlet.ShouldProcess($Name, "Execute snippet [$ext]")) {
        $displayContent = if ($tmpFile) { Get-Content $tmpFile -Raw -Encoding UTF8 } else { $content }
        Write-Host "What if: Executing snippet '$Name' [$ext]"
        Write-Host 'Content:'
        Write-Host $displayContent
        if ($resolvedVars.Count -gt 0) {
            $varDisplay = ($resolvedVars.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
            Write-Host "Resolved variables: $varDisplay"
        }
        if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        return
    }

    script:Out-Info "Running '$Name' [$ext] ..."
    Write-Host ""
    script:Write-AuditLog -Operation 'Execute' -SnippetName $Name

    # ── PSRemoting short-circuit ─────────────────────────────────────────────
    if ($ComputerName.Count -gt 0) {
        if ($ext -notin 'ps1','psm1') {
            Write-Error "PSRemoting (-ComputerName) only supports .ps1/.psm1 snippets. Got .$ext." -ErrorAction Continue
            return
        }
        $remoteContent = if ($tmpFile) { Get-Content $tmpFile -Raw -Encoding UTF8 } else { $content }
        $sb = [scriptblock]::Create($remoteContent)
        script:Out-Info ("Targeting computers: {0}" -f ($ComputerName -join ', '))
        Write-Host ""
        try {
            $icmParams = @{
                ComputerName = $ComputerName
                ScriptBlock  = $sb
                ArgumentList = $ArgumentList
            }
            if ($PSBoundParameters.ContainsKey('Credential')) { $icmParams['Credential'] = $Credential }
            Invoke-Command @icmParams
        } finally {
            if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        }
        try {
            $idxH = script:LoadIdx
            if ($idxH.snippets.ContainsKey($Name)) {
                $idxH.snippets[$Name].RunCount = $idxH.snippets[$Name].RunCount + 1
                $idxH.snippets[$Name].LastRun  = Get-Date
                script:SaveIdx -Idx $idxH
            }
        } catch { Write-Verbose "Run-history update failed (non-fatal): $_" }
        return
    }

    $snipStart = [datetime]::UtcNow
    try {
        switch ($ext) {
            { $_ -in 'ps1','psm1' } { & $runPath @ArgumentList }
            'py' {
                $py = @('python','python3') | Where-Object { Get-Command $_ -EA 0 } | Select-Object -First 1
                if ($py) { & $py $runPath @ArgumentList } else { Write-Error "Python not found in PATH." -ErrorAction Continue }
            }
            'js' {
                if (Get-Command node -EA 0) { & node $runPath @ArgumentList } else { Write-Error "Node.js not found in PATH." -ErrorAction Continue }
            }
            { $_ -in 'bat','cmd' } { & cmd /c $runPath @ArgumentList }
            'sh' {
                # Translate a Windows path to a WSL mount path (e.g. C:\foo\bar → /mnt/c/foo/bar)
                $wslPath = $runPath -replace '\\', '/'
                if ($wslPath -match '^([A-Za-z]):(.*)') {
                    $wslPath = '/mnt/' + $Matches[1].ToLower() + $Matches[2]
                }
                $wsl2Available = $false
                if (Get-Command wsl -EA 0) {
                    $wslStatus = & wsl --status 2>&1
                    $wsl2Available = ($wslStatus -join '') -match 'WSL\s*2|Default\s+Version:\s*2'
                    if (-not $wsl2Available) {
                        # Fallback check: wsl --list --verbose shows Version column
                        $wslList = & wsl --list --verbose 2>&1
                        $wsl2Available = ($wslList -join '') -match '\s2\s'
                    }
                }
                if ($wsl2Available) {
                    & wsl chmod +x $wslPath 2>$null
                    & wsl bash $wslPath @ArgumentList
                } elseif (Get-Command bash -EA 0) {
                    & bash $runPath @ArgumentList
                } elseif (Get-Command wsl -EA 0) {
                    & wsl chmod +x $wslPath 2>$null
                    & wsl bash $wslPath @ArgumentList
                } else {
                    Write-Error "Bash not found. Install WSL or Git Bash." -ErrorAction Continue
                }
            }
            'rb' {
                if (Get-Command ruby -EA 0) { & ruby $runPath @ArgumentList } else { Write-Error "Ruby not found in PATH." -ErrorAction Continue }
            }
            'go' {
                if (Get-Command go -EA 0) { & go run $runPath @ArgumentList } else { Write-Error "Go not found in PATH." -ErrorAction Continue }
            }
            'sql' {
                if (-not $ConnectionString) {
                    Write-Error "SQL snippet requires -ConnectionString. Example: Invoke-Snip myquery.sql -ConnectionString 'Server=.;Database=master;Integrated Security=True'" -ErrorAction Continue
                    return
                }
                $sqlContent = Get-Content $runPath -Raw -Encoding UTF8
                if (Get-Command Invoke-DbaQuery -EA 0) {
                    $results = Invoke-DbaQuery -SqlInstance $ConnectionString -Query $sqlContent
                    if ($null -ne $results) { $results | Format-Table -AutoSize }
                } else {
                    $conn = [System.Data.SqlClient.SqlConnection]::new($ConnectionString)
                    try {
                        $conn.Open()
                        $cmd = $conn.CreateCommand()
                        $cmd.CommandText = $sqlContent
                        $cmd.CommandTimeout = 30
                        $isSelect = $sqlContent.TrimStart() -imatch '^\s*(SELECT|WITH|EXEC(UTE)?)'
                        if ($isSelect) {
                            $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($cmd)
                            $ds = [System.Data.DataSet]::new()
                            $adapter.Fill($ds) | Out-Null
                            if ($ds.Tables.Count -gt 0) { $ds.Tables[0] | Format-Table -AutoSize }
                        } else {
                            $rowsAffected = $cmd.ExecuteNonQuery()
                            script:Out-OK "$rowsAffected row(s) affected."
                        }
                    } finally {
                        $conn.Close()
                        $conn.Dispose()
                    }
                }
            }
            default {
                script:Out-Warn "No built-in runner for '.$ext'. Opening with default app ..."
                Start-Process $runPath
            }
        }
        script:Invoke-SnipEvent -EventName 'SnipExecuted' -Data @{
            Name     = $Name
            Language = $ext
            Duration = ([datetime]::UtcNow - $snipStart).TotalSeconds
        }
    } finally {
        if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
    }

    # Update run history — wrapped in try/catch so a save failure never hides output
    try {
        $idxH = script:LoadIdx
        if ($idxH.snippets.ContainsKey($Name)) {
            $idxH.snippets[$Name].RunCount = $idxH.snippets[$Name].RunCount + 1
            $idxH.snippets[$Name].LastRun  = Get-Date
            script:SaveIdx -Idx $idxH
        }
    } catch { Write-Verbose "Run-history update failed (non-fatal): $_" }
}

function Get-SnipHistory {
    <#
    .SYNOPSIS
        Lists saved version history for a snippet.

    .DESCRIPTION
        Returns all timestamped version snapshots for the named snippet stored in
        the ~/.pssnips/history/<name> directory. Versions are listed newest first,
        numbered from 1 (most recent). Version snapshots are created automatically
        by Edit-Snip (before the editor opens), Add-Snip -Force, and New-Snip -Force
        -Content. Use Restore-Snip to roll back to any previous version.

    .PARAMETER Name
        Mandatory. The name of the snippet whose history to display.

    .EXAMPLE
        Get-SnipHistory my-snippet

        Lists all saved versions of 'my-snippet', newest first.

    .EXAMPLE
        $history = Get-SnipHistory my-snippet
        $history[0].Path  # path to the most recent version file

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has Version (int), Timestamp (datetime), Size (int), and
        Path (string) properties. Returns nothing when no history exists.

    .NOTES
        History snapshots are pruned automatically to MaxHistory (default 10)
        entries per snippet. Older snapshots are removed first when the limit is
        exceeded. The history directory is at ~/.pssnips/history/<snippetName>/.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to show history for')]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )
    script:InitEnv
    $histDir = Join-Path (Join-Path $script:Home 'history') $Name
    if (-not (Test-Path $histDir)) {
        script:Out-Info "No history for '$Name'."
        return @()
    }
    $files = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) {
        script:Out-Info "No history for '$Name'."
        return @()
    }

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    for ($i = 0; $i -lt $files.Count; $i++) {
        $f  = $files[$i]
        $ts = try { [datetime]::ParseExact($f.BaseName, 'yyyyMMddHHmmss', $null) } catch { $f.LastWriteTime }
        $rows.Add([pscustomobject]@{
            Version   = $i + 1
            Timestamp = $ts
            Size      = $f.Length
            Path      = $f.FullName
        })
    }

    Write-Host ""
    Write-Host ("  Version history for '{0}'" -f $Name) -ForegroundColor Cyan
    Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
    Write-Host ("  {0,-8} {1,-22} {2,-8} {3}" -f 'VERSION','TIMESTAMP','SIZE','PATH') -ForegroundColor DarkCyan
    foreach ($r in $rows) {
        Write-Host ("  {0,-8} {1,-22} {2,-8} {3}" -f $r.Version, ($r.Timestamp | Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $r.Size, $r.Path) -ForegroundColor Gray
    }
    Write-Host ""
    return $rows.ToArray()
}

function Restore-Snip {
    <#
    .SYNOPSIS
        Restores a snippet to a previous version from its version history.

    .DESCRIPTION
        Looks up the version history for the named snippet, saves the current content
        as a new history entry (to allow re-restore if needed), then copies the
        selected historical version back to the snippets directory and updates the
        snippet's 'modified' timestamp in the index. Version 1 is the most recent
        saved version, version 2 is the second most recent, and so on. Use
        Get-SnipHistory to see the available version numbers.

    .PARAMETER Name
        Mandatory. The name of the snippet to restore.

    .PARAMETER Version
        Optional. The version number to restore. 1 is the most recent saved version
        (default). Use Get-SnipHistory to see available version numbers.

    .EXAMPLE
        Restore-Snip my-snippet

        Restores 'my-snippet' to its most recent saved version (Version 1).

    .EXAMPLE
        Restore-Snip my-snippet -Version 3

        Restores 'my-snippet' to the third most recent saved version.

    .EXAMPLE
        Get-SnipHistory my-snippet
        Restore-Snip my-snippet -Version 2

        Lists versions, then restores the second most recent one.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a success or error message to the host.

    .NOTES
        The current snippet content is saved as a new history entry before
        overwriting, so you can re-restore the version you are replacing.
        Supports -WhatIf via SupportsShouldProcess.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to restore')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Position=1)]
        [int]$Version = 1
    )
    script:InitEnv
    $histDir = Join-Path (Join-Path $script:Home 'history') $Name
    if (-not (Test-Path $histDir)) {
        Write-Error "No history found for '$Name'." -ErrorAction Continue; return
    }
    $files = @(Get-ChildItem $histDir -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($files.Count -eq 0) {
        Write-Error "No history entries found for '$Name'." -ErrorAction Continue; return
    }
    if ($Version -lt 1 -or $Version -gt $files.Count) {
        Write-Error "Version $Version is out of range. Available: 1–$($files.Count)." -ErrorAction Continue; return
    }
    $histFile = $files[$Version - 1]
    $path = script:FindFile -Name $Name
    if (-not $path) {
        Write-Error "Snippet file for '$Name' not found." -ErrorAction Continue; return
    }

    if ($PSCmdlet.ShouldProcess($Name, "Restore version $Version")) {
        # Read restore content BEFORE saving current version (avoids same-second timestamp collision)
        $restoreContent = Get-Content $histFile.FullName -Raw -Encoding UTF8
        # Save current as new history entry before overwriting
        script:SaveVersion -Name $Name -FilePath $path
        Set-Content -Path $path -Value $restoreContent -Encoding UTF8
        # Update modified timestamp
        $idx = script:LoadIdx
        if ($idx.snippets.ContainsKey($Name)) {
            $idx.snippets[$Name].Modified = Get-Date
            script:SaveIdx -Idx $idx
        }
        script:Out-OK "Snippet '$Name' restored to version $Version ($(($histFile.LastWriteTime | Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))."
    }
}

function Test-Snip {
    <#
    .SYNOPSIS
        Runs PSScriptAnalyzer lint checks on a PowerShell snippet.

    .DESCRIPTION
        Resolves the snippet file path, verifies PSScriptAnalyzer is available, and
        runs Invoke-ScriptAnalyzer against the file. Results are displayed in a
        colour-coded table: errors in Red, warnings in Yellow, information in DarkCyan.
        When no issues are found a green success message is printed. Only applies to
        .ps1 and .psm1 files; an informational message is shown for other extensions.

    .PARAMETER Name
        Mandatory. The name of the snippet to analyse.

    .PARAMETER Severity
        Optional. Restrict results to a specific severity level: Error, Warning,
        Information, or ParseError. When omitted all severities are returned.

    .PARAMETER PassThru
        Optional switch. Returns the raw Invoke-ScriptAnalyzer result objects
        instead of printing the formatted table. Useful for scripted inspection.

    .EXAMPLE
        Test-Snip my-snippet

        Runs all PSScriptAnalyzer rules against 'my-snippet.ps1'.

    .EXAMPLE
        Test-Snip my-snippet -Severity Error

        Reports only Error-severity findings for 'my-snippet'.

    .EXAMPLE
        $results = Test-Snip my-snippet -PassThru
        $results | Where-Object Severity -eq 'Error'

        Returns raw result objects for further processing.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Only when -PassThru is specified. Otherwise writes to the host.

    .NOTES
        Requires the PSScriptAnalyzer module. Install with:
          Install-Module PSScriptAnalyzer -Scope CurrentUser
        Test-Snip only analyses .ps1 and .psm1 files. Other extensions receive
        an informational message and the function returns without error.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to analyse')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [ValidateSet('Error','Warning','Information','ParseError')]
        [string]$Severity = '',
        [switch]$PassThru
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $ext = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
    if ($ext -notin 'ps1','psm1') {
        script:Out-Info "Analysis only applies to PowerShell files (.ps1, .psm1). '$Name' is a .$ext file."
        return
    }

    $psa = @(Get-Module -ListAvailable -Name PSScriptAnalyzer -ErrorAction SilentlyContinue)
    if ($psa.Count -eq 0) {
        script:Out-Warn "PSScriptAnalyzer is not installed."
        script:Out-Info "Install it with: Install-Module PSScriptAnalyzer -Scope CurrentUser"
        return
    }

    Import-Module PSScriptAnalyzer -ErrorAction Stop

    $params = @{ Path = $path }
    if ($Severity) { $params['Severity'] = $Severity }
    $results = @(Invoke-ScriptAnalyzer @params -ErrorAction SilentlyContinue)

    if ($PassThru) { return $results }

    if ($results.Count -eq 0) {
        Write-Host ("  ✓ No issues found in '{0}'." -f $Name) -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host ("  PSScriptAnalyzer results for '{0}'" -f $Name) -ForegroundColor Cyan
    Write-Host "  $('─' * 70)" -ForegroundColor DarkGray
    Write-Host ("  {0,-40} {1,-12} {2,-5} {3}" -f 'RULE','SEVERITY','LINE','MESSAGE') -ForegroundColor DarkCyan
    foreach ($r in $results) {
        $color = switch ($r.Severity.ToString()) {
            'Error'       { 'Red' }
            'Warning'     { 'Yellow' }
            'Information' { 'DarkCyan' }
            default       { 'Gray' }
        }
        $rule = if ($r.RuleName.Length -gt 38) { $r.RuleName.Substring(0,35) + '...' } else { $r.RuleName }
        $msg  = if ($r.Message.Length -gt 40)  { $r.Message.Substring(0,37)  + '...' } else { $r.Message  }
        Write-Host ("  {0,-40} {1,-12} {2,-5} {3}" -f $rule, $r.Severity, $r.Line, $msg) -ForegroundColor $color
    }
    Write-Host ""
}

function Copy-Snip {
    <#
    .SYNOPSIS
        Copies a snippet's full content to the Windows clipboard.

    .DESCRIPTION
        Retrieves the content of the named snippet via Show-Snip -PassThru and
        passes it to Set-Clipboard. The function writes a confirmation message if
        successful and does nothing if the snippet is not found (Show-Snip handles
        the error message in that case).

    .PARAMETER Name
        Mandatory. The name of the snippet whose content should be copied.

    .EXAMPLE
        Copy-Snip my-snippet

        Copies the content of 'my-snippet' to the clipboard.

    .EXAMPLE
        # Quickly grab a snippet to paste into a terminal
        Copy-Snip azure-login
        # then Ctrl+V in any application

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host on success.

    .NOTES
        Requires a Windows clipboard (Set-Clipboard). In headless or SSH sessions
        where the clipboard is unavailable, Set-Clipboard may throw; the error is
        not suppressed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to copy')]
        [ValidateNotNullOrEmpty()]
        [string]$Name)
    $content = Show-Snip -Name $Name -PassThru
    if ($content) { Set-Clipboard -Value $content; script:Out-OK "'$Name' copied to clipboard." }
}

function Set-SnipTag {
    <#
    .SYNOPSIS
        Manages the tags on a local snippet: replace, add, or remove individual tags.
        Also supports pinning (favouriting) snippets.

    .DESCRIPTION
        Loads the snippet's current tags from index.json and applies one of three
        mutations depending on the parameters provided:
          -Tags    Replaces all existing tags with the supplied array.
          -Add     Appends each supplied tag that is not already present (no duplicates).
          -Remove  Removes each supplied tag from the current tag list.
        The updated tag list is saved back to index.json and the snippet's 'modified'
        timestamp is refreshed. Tags are stored as a string array in the index.

        Pin/Unpin operations are independent of tag operations and can be combined:
          -Pin     Marks the snippet as a favourite (pinned = $true).
          -Unpin   Removes the favourite mark (pinned = $false).

    .PARAMETER Name
        Mandatory. The name of the snippet to update.

    .PARAMETER Tags
        Optional. Replaces the snippet's entire tag set with these values.

    .PARAMETER Add
        Optional. Tags to append to the existing set. Duplicates are silently ignored.

    .PARAMETER Remove
        Optional. Tags to remove from the existing set. Tags not present are ignored.

    .PARAMETER Pin
        Optional switch. Marks the snippet as pinned (favourite). Pinned snippets
        appear at the top of all Get-Snip listings with a ★ indicator.

    .PARAMETER Unpin
        Optional switch. Removes the pinned (favourite) mark from the snippet.

    .EXAMPLE
        Set-SnipTag my-snippet -Tags @('devops', 'azure')

        Replaces all tags on 'my-snippet' with 'devops' and 'azure'.

    .EXAMPLE
        Set-SnipTag my-snippet -Add 'cloud'

        Appends the tag 'cloud' to the existing tags without removing any.

    .EXAMPLE
        Set-SnipTag my-snippet -Remove 'old-tag'

        Removes the tag 'old-tag' while keeping all other tags intact.

    .EXAMPLE
        Set-SnipTag my-snippet -Pin

        Marks 'my-snippet' as a favourite so it sorts to the top of all listings.

    .EXAMPLE
        Set-SnipTag my-snippet -Pin -Add 'cloud'

        Pins the snippet AND appends the tag 'cloud' in a single call.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message listing the updated tags.

    .NOTES
        Tags are normalised through [System.Collections.Generic.List[string]] to
        guarantee correct array serialisation in JSON (PowerShell 7.0+ ConvertTo-Json
        preserves single-element arrays natively, but the List normalisation is
        retained for defensive correctness).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage = 'Name of the snippet to tag')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [string[]]$Tags   = @(),
        [string[]]$Add    = @(),
        [string[]]$Remove = @(),
        [switch]$Pin,
        [switch]$Unpin
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }
    $current = [System.Collections.Generic.List[string]]@()
    if ($idx.snippets[$Name].Tags) {
        # [string[]]@() cast ensures AddRange receives a typed array even when
        # JSON deserialization returns a PSCustomObject or bare string for tags.
        $current.AddRange([string[]]@($idx.snippets[$Name].Tags))
    }
    if ($Tags)   { $current.Clear(); $current.AddRange($Tags) }
    foreach ($t in $Add)    { if ($t -notin $current) { $current.Add($t) } }
    foreach ($t in $Remove) { $current.Remove($t) | Out-Null }
    $idx.snippets[$Name].Tags     = $current.ToArray()
    $idx.snippets[$Name].Modified = Get-Date

    # Pin / Unpin — independent of tag operations
    if ($Pin)   { $idx.snippets[$Name].Pinned = $true  }
    if ($Unpin) { $idx.snippets[$Name].Pinned = $false }

    script:SaveIdx -Idx $idx
    script:Out-OK "Tags updated: $($current -join ', ')"
}

