# PSSnips — Analytics, statistics, scheduling, and event-registry functions.
# Get-StaleSnip, Get-SnipStats, Export-VSCodeSnips, Invoke-FuzzySnip

function Get-StaleSnip {
    <#
    .SYNOPSIS
        Lists snippets that have not been run in N days (or have never been run).

    .DESCRIPTION
        Reads the snippet index and identifies snippets whose last execution date
        falls at or beyond the specified staleness threshold. Optionally includes
        snippets that have no recorded execution at all. Results are sorted with
        the most idle snippets first. Use -PassThru to receive the objects
        directly for further pipeline processing instead of displaying the table.

    .PARAMETER DaysUnused
        The staleness threshold in days. Snippets whose last run was at least this
        many days ago are included. Defaults to 90.

    .PARAMETER IncludeNeverRun
        When specified, snippets with no recorded run (runCount is absent or zero)
        are also included in the results. They are shown with DaysIdle = MaxValue
        and sorted to the bottom of the list (after legitimately stale snippets).

    .PARAMETER PassThru
        When specified, suppresses the formatted table output and returns the
        result objects directly so they can be piped to further commands.

    .EXAMPLE
        Get-StaleSnip

        Lists all snippets that have not been run in 90 or more days.

    .EXAMPLE
        Get-StaleSnip -DaysUnused 30 -IncludeNeverRun

        Lists snippets idle for 30+ days plus any that have never been run.

    .EXAMPLE
        Get-StaleSnip -DaysUnused 60 -PassThru | Remove-Snip

        Retrieves stale snippet objects and pipes their names to Remove-Snip.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: Name, Language, Tags, LastRun, DaysIdle, RunCount.

    .NOTES
        DaysIdle is computed from [datetime]::Now. Snippets with no lastRun entry
        and -IncludeNeverRun will show DaysIdle as 2147483647 ([int]::MaxValue).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateRange(0, [int]::MaxValue)]
        [int]$DaysUnused = 90,
        [switch]$IncludeNeverRun,
        [switch]$PassThru
    )
    script:InitEnv
    $idx = script:LoadIdx

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($name in $idx.snippets.Keys) {
        $entry    = $idx.snippets[$name]
        $hasRun   = $null -ne $entry.LastRun
        $runCount = $entry.RunCount

        if ($hasRun) {
            $daysIdle = ([datetime]::Now - [datetime]$entry.LastRun).Days
        } elseif ($IncludeNeverRun) {
            $daysIdle = [int]::MaxValue
        } else {
            continue
        }

        if ($daysIdle -ge $DaysUnused) {
            $results.Add([pscustomobject]@{
                Name     = $name
                Language = $entry.Language
                Tags     = @($entry.Tags) -join ', '
                LastRun  = if ($hasRun) { ([datetime]$entry.LastRun) | Get-Date -Format 'yyyy-MM-dd' } else { 'Never' }
                DaysIdle = if ($daysIdle -eq [int]::MaxValue) { '∞' } else { $daysIdle }
                RunCount = $runCount
            })
        }
    }

    # Sort: finite DaysIdle descending, then never-run entries last
    $sorted = @($results | Sort-Object {
        if ($_.DaysIdle -eq '∞') { [int]::MaxValue } else { [int]$_.DaysIdle }
    } -Descending)

    if (-not $PassThru) {
        if ($sorted.Count -eq 0) {
            script:Out-Info "No stale snippets found (threshold: $DaysUnused days)."
        } else {
            Write-Host ""
            Write-Host "  Stale Snippets  (idle ≥ $DaysUnused days)" -ForegroundColor Cyan
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            Write-Host ("  {0,-23} {1,-5} {2,-10} {3,-8} {4}" -f 'NAME','LANG','LAST RUN','DAYS IDLE','TAGS') -ForegroundColor DarkCyan
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            foreach ($r in $sorted) {
                $c = script:LangColor -ext $r.Language
                Write-Host ("  {0,-23} " -f $r.Name) -ForegroundColor $c -NoNewline
                Write-Host ("{0,-5} {1,-10} {2,-8} {3}" -f $r.Language, $r.LastRun, $r.DaysIdle, $r.Tags) -ForegroundColor Gray
            }
            Write-Host ""
        }
    }

    return $sorted
}

function Get-SnipStats {
    <#
    .SYNOPSIS
        Shows execution analytics — run counts, last run times, and usage leaderboard.

    .DESCRIPTION
        Reads the snippet index and builds a ranked leaderboard of the most frequently
        or most recently run snippets. Snippets that have never been run are included
        with a RunCount of 0. Use -All to see the full collection rather than just
        the top N entries. Use -PassThru to receive the ranked objects for pipeline
        processing without printing the table.

    .PARAMETER Top
        The number of top entries to display. Defaults to 10. Ignored when -All is set.

    .PARAMETER SortBy
        The field used to rank and sort results. Valid values:
          RunCount  – most-run snippets first (default)
          LastRun   – most-recently run snippets first
          Name      – alphabetical ascending

    .PARAMETER All
        When specified, all snippets are included regardless of -Top.

    .PARAMETER PassThru
        When specified, suppresses the formatted table and returns the ranked
        objects directly for pipeline use.

    .EXAMPLE
        Get-SnipStats

        Displays the top 10 snippets by run count.

    .EXAMPLE
        Get-SnipStats -Top 20 -SortBy LastRun

        Displays the 20 most-recently run snippets.

    .EXAMPLE
        Get-SnipStats -All -PassThru | Export-Csv stats.csv -NoTypeInformation

        Returns all snippet stat objects and exports them to CSV.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: Rank, Name, Language, RunCount, LastRun, Tags.

    .NOTES
        Snippets with no runCount entry are treated as RunCount = 0.
        Snippets with no lastRun entry are shown as LastRun = 'Never'.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Top = 10,
        [ValidateSet('RunCount','LastRun','Name')]
        [string]$SortBy = 'RunCount',
        [switch]$All,
        [switch]$PassThru
    )
    script:InitEnv
    $idx = script:LoadIdx

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($name in $idx.snippets.Keys) {
        $entry    = $idx.snippets[$name]
        $runCount = $entry.RunCount
        $lastRun  = if ($null -ne $entry.LastRun) {
            ([datetime]$entry.LastRun) | Get-Date -Format 'yyyy-MM-dd HH:mm'
        } else { 'Never' }
        $rows.Add([pscustomobject]@{
            Rank     = 0   # assigned after sort
            Name     = $name
            Language = $entry.Language
            RunCount = $runCount
            LastRun  = $lastRun
            Tags     = @($entry.Tags) -join ', '
        })
    }

    $sorted = switch ($SortBy) {
        'RunCount' { @($rows | Sort-Object RunCount -Descending) }
        'LastRun'  {
            # 'Never' entries sort to bottom
            @($rows | Sort-Object {
                if ($_.LastRun -eq 'Never') { [datetime]::MinValue } else { [datetime]$_.LastRun }
            } -Descending)
        }
        'Name'     { @($rows | Sort-Object Name) }
        default    { @($rows | Sort-Object RunCount -Descending) }
    }

    if (-not $All) { $sorted = @($sorted | Select-Object -First $Top) }

    # Assign 1-based rank
    for ($i = 0; $i -lt $sorted.Count; $i++) { $sorted[$i].Rank = $i + 1 }

    if (-not $PassThru) {
        if ($sorted.Count -eq 0) {
            script:Out-Info "No snippets found."
        } else {
            $neverRun = @($sorted | Where-Object { $_.RunCount -eq 0 }).Count
            Write-Host ""
            Write-Host "  Snippet Execution Statistics" -ForegroundColor Cyan
            $subtitle = if ($All) { "All $($sorted.Count) snippets" } else { "Top $($sorted.Count)" }
            Write-Host "  $subtitle · sorted by $SortBy" -ForegroundColor DarkGray
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            Write-Host ("  {0,4}  {1,-23} {2,-5} {3,8}  {4,-17} {5}" -f '#','NAME','LANG','RUNS','LAST RUN','TAGS') -ForegroundColor DarkCyan
            Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
            foreach ($r in $sorted) {
                $c        = script:LangColor -ext $r.Language
                $runsDisp = if ($r.RunCount -gt 0) { "$($r.RunCount)" } else { '—' }
                Write-Host ("  {0,4}  {1,-23} " -f $r.Rank, $r.Name) -ForegroundColor $c -NoNewline
                Write-Host ("{0,-5} {1,8}  {2,-17} {3}" -f $r.Language, $runsDisp, $r.LastRun, $r.Tags) -ForegroundColor Gray
            }
            Write-Host ""
            if ($neverRun -eq $sorted.Count) {
                script:Out-Info "No snippets have been run yet. Use 'snip run <name>' to execute one."
            }
        }
    }

    return $sorted
}

function Export-VSCodeSnips {
    <#
    .SYNOPSIS
        Exports the PSSnips collection to VS Code user snippets format.

    .DESCRIPTION
        Reads local snippets and writes them as VS Code user snippet JSON files
        (one file per language) to the VS Code User snippets directory. Each snippet
        is written in the standard VS Code format with prefix, body array, and
        description fields. Use -Language to export only one language. Use -WhatIf
        to preview what would be written without touching any files. Use -PassThru
        to receive the generated JSON hashtable objects for further processing.

        Auto-detected VS Code snippets directory locations (in preference order):
          %APPDATA%\Code\User\snippets          (VS Code Stable)
          %APPDATA%\Code - Insiders\User\snippets  (VS Code Insiders)

        Language-to-filename mapping:
          ps1/psm1 → powershell.json    py  → python.json
          js       → javascript.json    ts  → typescript.json
          sh/bash  → shellscript.json   rb  → ruby.json
          go       → go.json            sql → sql.json
          md       → markdown.json      txt/other → plaintext.json

    .PARAMETER Language
        Optional. Filter to a single language extension (e.g., 'ps1', 'py', 'js').
        When omitted all languages present in the index are exported.

    .PARAMETER OutputDir
        Optional. Path to the VS Code snippets directory. When omitted the
        auto-detected path is used. The directory must already exist.

    .PARAMETER WhatIf
        When specified, prints "Would write <path>" for each file that would be
        written without actually writing anything.

    .PARAMETER PassThru
        When specified, returns the generated snippet hashtables keyed by output
        file path instead of (or in addition to) writing them.

    .EXAMPLE
        Export-VSCodeSnips

        Exports all snippets to the auto-detected VS Code snippets directory.

    .EXAMPLE
        Export-VSCodeSnips -Language ps1 -WhatIf

        Previews what would be written for PowerShell snippets only.

    .EXAMPLE
        Export-VSCodeSnips -OutputDir 'C:\MySnippets'

        Exports all snippets to a custom directory.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable (keyed by output path) when -PassThru is set.
        Otherwise None — writes files and prints confirmation messages.

    .NOTES
        Snippet file content is split on newlines to produce the VS Code body array.
        If the VS Code snippets directory cannot be detected and -OutputDir is not
        provided, the function warns and exits without writing any files.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([hashtable])]
    param(
        [string]$Language  = '',
        [string]$OutputDir = '',
        [switch]$PassThru
    )
    script:InitEnv

    # ── Resolve output directory ────────────────────────────────────────────
    $resolvedDir = $OutputDir
    if (-not $resolvedDir) {
        $candidates = @(
            (Join-Path $env:APPDATA 'Code\User\snippets'),
            (Join-Path $env:APPDATA 'Code - Insiders\User\snippets')
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $resolvedDir = $c; break }
        }
    }
    if (-not $resolvedDir -or -not (Test-Path $resolvedDir)) {
        script:Out-Warn "VS Code snippets directory not found. Provide -OutputDir or install VS Code."
        return
    }

    # ── Language → VS Code filename map ────────────────────────────────────
    $langMap = @{
        ps1  = 'powershell.json';  psm1 = 'powershell.json'
        py   = 'python.json'
        js   = 'javascript.json'
        ts   = 'typescript.json'
        sh   = 'shellscript.json'; bash = 'shellscript.json'
        rb   = 'ruby.json'
        go   = 'go.json'
        sql  = 'sql.json'
        md   = 'markdown.json'
    }

    $idx = script:LoadIdx

    # ── Group snippets by VS Code output file ──────────────────────────────
    $byFile = @{}   # outPath → hashtable of VS Code snippet entries
    foreach ($name in $idx.snippets.Keys) {
        $entry = $idx.snippets[$name]
        $lang  = $entry.Language
        if ($Language -and $lang -ne $Language) { continue }

        $vsFile = if ($langMap.ContainsKey($lang)) { $langMap[$lang] } else { 'plaintext.json' }
        $outPath = Join-Path $resolvedDir $vsFile

        $snipPath = script:FindFile -Name $name
        if (-not $snipPath -or -not (Test-Path $snipPath)) { continue }

        $bodyLines = @(Get-Content $snipPath -Encoding UTF8)
        $desc = if ($entry.Description) { $entry.Description } else { $name }

        if (-not $byFile.ContainsKey($outPath)) { $byFile[$outPath] = @{} }
        $byFile[$outPath][$name] = @{
            prefix      = $name
            body        = $bodyLines
            description = $desc
        }
    }

    if ($byFile.Count -eq 0) {
        script:Out-Info "No snippets to export$(if ($Language) { " for language '$Language'" })."
        return
    }

    $passThruResult = @{}

    foreach ($outPath in ($byFile.Keys | Sort-Object)) {
        $fileSnips = $byFile[$outPath]

        # Merge with existing VS Code snippets file when present
        $merged = @{}
        if (Test-Path $outPath) {
            try {
                $existing = Get-Content $outPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -AsHashtable
                foreach ($k in $existing.Keys) { $merged[$k] = $existing[$k] }
            } catch { Write-Verbose "Export-VSCodeSnips: could not read existing file '$outPath' — overwriting." }
        }
        foreach ($k in $fileSnips.Keys) { $merged[$k] = $fileSnips[$k] }

        if ($WhatIf -or $PSCmdlet.ShouldProcess($outPath, 'Write VS Code snippets file')) {
            if ($WhatIf) {
                script:Out-Info "Would write $($fileSnips.Count) snippet(s) → $outPath"
            } else {
                $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $outPath -Encoding UTF8
                script:Out-OK "Wrote $($fileSnips.Count) snippet(s) → $outPath"
            }
        }

        if ($PassThru) { $passThruResult[$outPath] = $merged }
    }

    if ($PassThru) { return $passThruResult }
}

function Invoke-FuzzySnip {
    <#
    .SYNOPSIS
        Launches an interactive fuzzy-finder picker for snippets using fzf.

    .DESCRIPTION
        Pipes all snippet names to fzf (or PSFzf's Invoke-Fzf) for interactive
        fuzzy selection, then executes the chosen action — Show, Run, or Edit — on
        the selected snippet. Requires fzf on PATH or the PSFzf module installed.
        When neither is available, falls back to Get-Snip to list snippets with a
        warning explaining how to install fzf.

    .PARAMETER Action
        The action to execute on the selected snippet:
          Show  – display the snippet content (default)
          Run   – execute the snippet via Invoke-Snip
          Edit  – open the snippet in the configured editor via Edit-Snip

    .PARAMETER Filter
        Optional pre-filter string passed to fzf via --query so the picker opens
        with the search box already populated.

    .EXAMPLE
        Invoke-FuzzySnip

        Opens the fuzzy picker; pressing Enter on a selection shows it.

    .EXAMPLE
        Invoke-FuzzySnip -Action Run

        Opens the fuzzy picker and runs the selected snippet.

    .EXAMPLE
        Invoke-FuzzySnip -Action Edit -Filter azure

        Opens the fuzzy picker pre-filtered to 'azure' and edits the selection.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String
        The name of the selected snippet, or nothing if the user pressed Esc.

    .NOTES
        Install fzf:      winget install fzf
        Install PSFzf:    Install-Module PSFzf
        If only PSFzf is available (without the raw fzf binary on PATH), Invoke-Fzf
        from that module is used instead of piping to fzf directly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('Show','Run','Edit')]
        [string]$Action = 'Show',
        [string]$Filter = ''
    )
    script:InitEnv
    $idx = script:LoadIdx

    if ($idx.snippets.Count -eq 0) {
        script:Out-Info "No snippets yet. Use 'snip new <name>' to create one."
        return
    }

    $names = @($idx.snippets.Keys | Sort-Object)

    $fzfAvailable  = [bool](Get-Command fzf -ErrorAction SilentlyContinue)
    $psFzfAvailable = [bool](Get-Module -ListAvailable PSFzf -ErrorAction SilentlyContinue)

    if (-not $fzfAvailable -and -not $psFzfAvailable) {
        Write-Warning "fzf not found. Install via: winget install fzf  or: Install-Module PSFzf"
        Get-Snip
        return
    }

    $selected = $null

    if ($fzfAvailable) {
        $modulePath = $PSScriptRoot
        $previewCmd = "pwsh -NoProfile -Command `"Import-Module '$modulePath\PSSnips.psm1' -Force; Show-Snip -Name '{}'`""
        $fzfArgs    = @('--height','40%','--reverse','--preview',$previewCmd)
        if ($Filter) { $fzfArgs += @('--query', $Filter) }
        $selected = $names | & fzf @fzfArgs
    } elseif ($psFzfAvailable) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        $fzfParams = @{ Input = $names }
        if ($Filter) { $fzfParams['Query'] = $Filter }
        $selected = Invoke-Fzf @fzfParams
    }

    if (-not $selected) { return }   # user pressed Esc or made no selection

    switch ($Action) {
        'Show' { Show-Snip  -Name $selected }
        'Run'  { Invoke-Snip -Name $selected }
        'Edit' { Edit-Snip   -Name $selected }
    }

    return $selected
}

function Add-SnipTerminalProfile {
    <#
    .SYNOPSIS
        Adds a PSSnips TUI profile to Windows Terminal.

    .DESCRIPTION
        Injects a PSSnips profile entry, a matching colour scheme, and an
        optional keybinding into the Windows Terminal settings.json file.

        Detects the correct settings.json path automatically, checking for
        Windows Terminal Stable, Preview, and unpackaged (portable) installs in
        that order. If multiple installs are present, only the first detected
        path is modified unless -Path is specified explicitly.

        Does not modify any file when -WhatIf is specified. If the PSSnips
        profile already exists and -Force is not set, the function warns and
        returns without modifying anything.

    .PARAMETER Keybinding
        Keyboard shortcut used to open the PSSnips TUI in a new tab.
        Defaults to 'ctrl+alt+s'. Pass an empty string to skip adding a
        keybinding entry entirely.

    .PARAMETER Font
        Font face to use inside the PSSnips profile. Defaults to 'Cascadia Code'.
        Any font installed on the system may be specified.

    .PARAMETER Path
        Explicit path to a Windows Terminal settings.json file. When omitted the
        function auto-detects the correct location.

    .PARAMETER Force
        Overwrites an existing PSSnips profile and colour scheme if they are
        already present in settings.json.

    .EXAMPLE
        Add-SnipTerminalProfile

        Adds the PSSnips profile with default settings: Ctrl+Alt+S keybinding,
        Cascadia Code font, and the PSSnips colour scheme.

    .EXAMPLE
        Add-SnipTerminalProfile -Keybinding 'ctrl+shift+s' -Font 'JetBrains Mono'

        Adds the profile with a custom keybinding and font face.

    .EXAMPLE
        Add-SnipTerminalProfile -WhatIf

        Shows what would be changed without writing to settings.json.

    .EXAMPLE
        Add-SnipTerminalProfile -Force

        Re-applies the PSSnips profile and colour scheme even if already present.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String
        The path to the settings.json file that was (or would be) modified.

    .NOTES
        Requires Windows Terminal (Stable or Preview) to be installed.
        Install via: winget install Microsoft.WindowsTerminal

        The injected colour scheme is named 'PSSnips' and uses a dark theme
        based on the Catppuccin Mocha palette. Colours can be customised by
        editing settings.json after the profile is created.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [string]$Keybinding = 'ctrl+alt+s',
        [string]$Font       = 'Cascadia Code',
        [string]$Path       = '',
        [switch]$Force
    )

    # ── Locate settings.json ──────────────────────────────────────────────────
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )

    $settingsPath = if ($Path) {
        $Path
    } else {
        $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if (-not $settingsPath -or -not (Test-Path $settingsPath)) {
        Write-Error "Windows Terminal settings.json not found. Install Windows Terminal: winget install Microsoft.WindowsTerminal"
        return
    }

    # ── Load settings ─────────────────────────────────────────────────────────
    $raw      = Get-Content -Raw -LiteralPath $settingsPath
    $settings = $raw | ConvertFrom-Json -AsHashtable

    # Ensure required top-level keys exist
    if (-not $settings.ContainsKey('profiles'))  { $settings['profiles']  = @{} }
    if (-not $settings.profiles.ContainsKey('list')) { $settings.profiles['list'] = @() }
    if (-not $settings.ContainsKey('schemes'))   { $settings['schemes']   = @() }
    if (-not $settings.ContainsKey('actions'))   { $settings['actions']   = @() }

    # ── Check for existing profile ────────────────────────────────────────────
    $existingProfile = @($settings.profiles.list) | Where-Object { $_.name -eq 'PSSnips TUI' }

    if ($existingProfile -and -not $Force) {
        Write-Warning "PSSnips profile already exists in settings.json. Use -Force to overwrite."
        return $settingsPath
    }

    # ── PSSnips colour scheme (Catppuccin Mocha-inspired) ─────────────────────
    $scheme = [ordered]@{
        name                = 'PSSnips'
        background          = '#1E1E2E'
        foreground          = '#CDD6F4'
        cursorColor         = '#F5E0DC'
        selectionBackground = '#313244'
        black               = '#45475A'
        blue                = '#89B4FA'
        brightBlack         = '#585B70'
        brightBlue          = '#89B4FA'
        brightCyan          = '#94E2D5'
        brightGreen         = '#A6E3A1'
        brightPurple        = '#F5C2E7'
        brightRed           = '#F38BA8'
        brightWhite         = '#A6ADC8'
        brightYellow        = '#F9E2AF'
        cyan                = '#89DCEB'
        green               = '#A6E3A1'
        purple              = '#CBA6F7'
        red                 = '#F38BA8'
        white               = '#BAC2DE'
        yellow              = '#F9E2AF'
    }

    # ── PSSnips Terminal profile ───────────────────────────────────────────────
    $profileEntry = [ordered]@{
        guid         = '{d6f4b8e3-1c72-4a59-b031-7e5f93c2084a}'
        name         = 'PSSnips TUI'
        commandline  = 'pwsh.exe -NoProfile -Command "Import-Module PSSnips -ErrorAction Stop; Start-SnipManager"'
        colorScheme  = 'PSSnips'
        tabTitle     = 'PSSnips'
        startingDirectory = '%USERPROFILE%'
        hidden       = $false
    }

    if ($Font) {
        $profileEntry['font'] = @{ face = $Font }
    }

    # ── Apply changes ─────────────────────────────────────────────────────────
    $action = if ($existingProfile) { "Overwrite PSSnips profile in" } else { "Add PSSnips profile to" }

    if ($PSCmdlet.ShouldProcess($settingsPath, $action)) {

        # Update or add colour scheme
        $schemeList  = [System.Collections.Generic.List[object]](@($settings.schemes))
        $existingIdx = $null
        for ($i = 0; $i -lt $schemeList.Count; $i++) {
            if ($schemeList[$i].name -eq 'PSSnips') { $existingIdx = $i; break }
        }
        if ($null -ne $existingIdx) { $schemeList[$existingIdx] = $scheme }
        else                        { $schemeList.Add($scheme) }
        $settings['schemes'] = $schemeList.ToArray()

        # Update or add profile
        $profileList = [System.Collections.Generic.List[object]](@($settings.profiles.list))
        $profIdx     = $null
        for ($i = 0; $i -lt $profileList.Count; $i++) {
            if ($profileList[$i].name -eq 'PSSnips TUI') { $profIdx = $i; break }
        }
        if ($null -ne $profIdx) { $profileList[$profIdx] = $profileEntry }
        else                    { $profileList.Add($profileEntry) }
        $settings.profiles['list'] = $profileList.ToArray()

        # Add keybinding if requested and not already present
        if ($Keybinding) {
            $actionList = [System.Collections.Generic.List[object]](@($settings.actions))
            $kbExists   = @($actionList) | Where-Object {
                $_.keys -eq $Keybinding -and
                ($_.command -is [hashtable] -or $_.command -is [System.Collections.Hashtable]) -and
                $_.command.profile -eq 'PSSnips TUI'
            }
            if (-not $kbExists) {
                $actionList.Add([ordered]@{
                    command = [ordered]@{ action = 'newTab'; profile = 'PSSnips TUI' }
                    keys    = $Keybinding
                })
            }
            $settings['actions'] = $actionList.ToArray()
        }

        # Write back with 4-space indentation (matches WT defaults)
        $settings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $settingsPath -Encoding UTF8

        script:Out-Ok "PSSnips profile added to Windows Terminal."
        Write-Host "  Settings : $settingsPath" -ForegroundColor DarkGray
        if ($Keybinding) {
            Write-Host "  Keybind  : $Keybinding  → opens PSSnips TUI in new tab" -ForegroundColor DarkGray
        }
        Write-Host "  Scheme   : PSSnips (Catppuccin Mocha-inspired dark theme)" -ForegroundColor DarkGray
        Write-Host "  Font     : $Font" -ForegroundColor DarkGray
    }

    return $settingsPath
}

function Get-SnipAuditLog {
    <#
    .SYNOPSIS
        Reads and filters the PSSnips audit log.

    .DESCRIPTION
        Reads ~/.pssnips/audit.log, parses each NDJSON line, and returns matching
        entries newest-first. Use -Last to limit the number of results, -Operation to
        filter by operation type (Create, Edit, Delete, Execute, Export, Import), and
        -SnippetName to filter by snippet name. Results are displayed as a formatted
        table showing Timestamp, Operation, SnippetName, and User.

    .PARAMETER Last
        Maximum number of entries to return, newest first. Default: 50.

    .PARAMETER Operation
        Optional. Filter entries to a specific operation type:
        Create, Edit, Delete, Execute, Export, or Import.

    .PARAMETER SnippetName
        Optional. Filter entries to a specific snippet name.

    .EXAMPLE
        Get-SnipAuditLog

        Displays the last 50 audit log entries.

    .EXAMPLE
        Get-SnipAuditLog -Operation Execute -Last 10

        Displays the last 10 execution events.

    .EXAMPLE
        Get-SnipAuditLog -SnippetName deploy-script

        Displays all audit events for the 'deploy-script' snippet.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: Timestamp, Operation, SnippetName, User.

    .NOTES
        The audit log is written to ~/.pssnips/audit.log in NDJSON format.
        The log is automatically rotated when it exceeds 10 MB (renamed to audit.log.1).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Last = 50,
        [string]$Operation   = '',
        [string]$SnippetName = ''
    )
    script:InitEnv
    $auditFile = Join-Path $script:Home 'audit.log'
    if (-not (Test-Path $auditFile)) {
        script:Out-Info 'No audit log found.'
        return @()
    }

    $lines   = @(Get-Content $auditFile -Encoding UTF8 -ErrorAction SilentlyContinue)
    $entries = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($line in $lines) {
        if (-not $line.Trim()) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($Operation   -and $obj.operation   -ne $Operation)   { continue }
            if ($SnippetName -and $obj.snippetName  -ne $SnippetName) { continue }
            $entries.Add([pscustomobject]@{
                Timestamp   = $obj.timestamp
                Operation   = $obj.operation
                SnippetName = $obj.snippetName
                User        = $obj.user
            })
        } catch { continue }
    }

    $result = @($entries | Select-Object -Last $Last | Sort-Object Timestamp -Descending)

    if ($result.Count -eq 0) {
        script:Out-Info 'No audit log entries found.'
        return @()
    }

    Write-Host ''
    Write-Host '  PSSnips Audit Log' -ForegroundColor Cyan
    Write-Host "  $('─' * 80)" -ForegroundColor DarkGray
    Write-Host ("  {0,-28} {1,-10} {2,-25} {3}" -f 'TIMESTAMP', 'OPERATION', 'SNIPPET', 'USER') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 80)" -ForegroundColor DarkGray
    foreach ($r in $result) {
        $ts = try { [datetime]$r.Timestamp | Get-Date -Format 'yyyy-MM-dd HH:mm:ss' } catch { $r.Timestamp }
        Write-Host ("  {0,-28} {1,-10} {2,-25} {3}" -f $ts, $r.Operation, $r.SnippetName, $r.User) -ForegroundColor Gray
    }
    Write-Host ''
    return $result
}

function Set-SnipRating {
    <#
    .SYNOPSIS
        Sets a star rating (1–5) on a snippet.

    .DESCRIPTION
        Updates the snippet's index entry with a numeric rating (1–5 stars) and a
        'ratedAt' timestamp. The rating is stored in index.json alongside the snippet
        metadata.

    .PARAMETER Name
        Mandatory. The name of the snippet to rate.

    .PARAMETER Stars
        Mandatory. The star rating, between 1 and 5 inclusive.

    .EXAMPLE
        Set-SnipRating -Name deploy-script -Stars 5

        Rates the 'deploy-script' snippet as 5 stars.

    .EXAMPLE
        Set-SnipRating azure-login -Stars 4

        Rates 'azure-login' as 4 stars.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host.

    .NOTES
        Ratings are stored in index.json alongside the snippet metadata.
        The 'ratedAt' timestamp uses ISO 8601 format.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to rate')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory, Position=1, HelpMessage='Star rating 1-5')]
        [ValidateRange(1, 5)]
        [int]$Stars
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) {
        Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return
    }
    if (-not $PSCmdlet.ShouldProcess($Name, "Set rating to $Stars star$(if ($Stars -ne 1) {'s'})")) { return }
    try {
        $idx.snippets[$Name].Rating  = $Stars
        Add-Member -InputObject $idx.snippets[$Name] -NotePropertyName 'RatedAt' -NotePropertyValue (Get-Date -Format 'o') -Force
        script:SaveIdx -Idx $idx
        script:Out-OK "Snippet '$Name' rated $Stars star$(if ($Stars -ne 1) {'s'})."
    } catch {
        script:Out-Err "Failed to save rating: $_"
    }
}

function Add-SnipComment {
    <#
    .SYNOPSIS
        Appends a comment to a snippet's comment log.

    .DESCRIPTION
        Adds a timestamped comment to ~/.pssnips/comments/<name>.json. The file is a
        JSON array; a new entry is appended with each call. Each comment includes a
        timestamp (ISO 8601), the current user's name, and the comment text. Use
        Show-Snip -Comments to display comments alongside the snippet content.

    .PARAMETER Name
        Mandatory. The name of the snippet to comment on.

    .PARAMETER Text
        Mandatory. The comment text to append.

    .EXAMPLE
        Add-SnipComment -Name deploy-script -Text 'Tested on prod 2024-01-15 — works.'

        Appends a comment to the 'deploy-script' snippet.

    .EXAMPLE
        Add-SnipComment azure-login 'Remember to refresh token monthly'

        Shorthand positional form.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host.

    .NOTES
        Comments are stored in ~/.pssnips/comments/<name>.json as a JSON array.
        The directory is created automatically if it does not exist.
        Use Show-Snip -Comments to view comments alongside snippet content.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to comment on')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory, Position=1, HelpMessage='Comment text')]
        [ValidateNotNullOrEmpty()]
        [string]$Text
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) {
        Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return
    }
    try {
        $commentsDir  = Join-Path $script:Home 'comments'
        if (-not (Test-Path $commentsDir)) { New-Item -ItemType Directory -Path $commentsDir -Force | Out-Null }
        $commentsFile = Join-Path $commentsDir "$Name.json"
        $existing     = if (Test-Path $commentsFile) {
            try { @(Get-Content $commentsFile -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json) } catch { @() }
        } else { @() }
        $newComment = [ordered]@{
            timestamp = (Get-Date -Format 'o')
            author    = $env:USERNAME
            text      = $Text
        }
        $updated = @($existing) + @($newComment)
        $updated | ConvertTo-Json -Depth 5 | Set-Content $commentsFile -Encoding UTF8
        script:Out-OK "Comment added to '$Name'."
    } catch {
        script:Out-Err "Failed to add comment: $_"
    }
}


function New-SnipSchedule {
    <#
    .SYNOPSIS
        Schedules a snippet to run automatically via Windows Task Scheduler.

    .DESCRIPTION
        Creates a Windows Scheduled Task that runs the named snippet using
        Invoke-Snip. The task action runs:
            pwsh -NonInteractive -Command "Import-Module PSSnips; Invoke-Snip '<Name>'"
        Schedule can be a named trigger (Daily, Weekly, Hourly, OnLogon, OnStartup)
        or a free-form string stored in metadata for reference. Use -At to specify
        a start time and -RepeatInterval for custom repetition. Task metadata is
        persisted to ~/.pssnips/schedules.json.

    .PARAMETER Name
        Mandatory. The name of the snippet to schedule.

    .PARAMETER Schedule
        Mandatory. Named trigger or schedule string:
          Daily, Weekly, Hourly, OnLogon, OnStartup
        A free-form cron string is also accepted and stored in metadata.

    .PARAMETER Description
        Optional. A description for the scheduled task.

    .PARAMETER At
        Optional. The start time for Daily or Weekly schedules.
        Defaults to the current time when not specified.

    .PARAMETER RepeatInterval
        Optional. A TimeSpan specifying how often to repeat the trigger.

    .EXAMPLE
        New-SnipSchedule -Name cleanup-logs -Schedule Daily -At '02:00'

        Schedules 'cleanup-logs' to run every day at 02:00.

    .EXAMPLE
        New-SnipSchedule -Name health-check -Schedule Hourly

        Schedules 'health-check' to run every hour.

    .EXAMPLE
        New-SnipSchedule -Name startup-init -Schedule OnStartup

        Schedules 'startup-init' to run at system startup.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host.

    .NOTES
        Requires Windows Task Scheduler (available on all modern Windows systems).
        The task is registered under the current user account.
        Task output is appended to ~/.pssnips/schedule.log.
        Schedule metadata is stored in ~/.pssnips/schedules.json.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name to schedule')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [Parameter(Mandatory, Position=1, HelpMessage='Schedule trigger')]
        [ValidateNotNullOrEmpty()]
        [string]$Schedule,
        [string]$Description     = '',
        [datetime]$At            = (Get-Date),
        [timespan]$RepeatInterval = [timespan]::Zero
    )
    script:InitEnv
    $idx = script:LoadIdx
    if (-not $idx.snippets.ContainsKey($Name)) {
        Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return
    }

    $taskName   = "PSSnips_$Name"
    $logFile    = Join-Path $script:Home 'schedule.log'
    $actionArgs = "-NonInteractive -Command `"Import-Module PSSnips -ErrorAction Stop; Invoke-Snip '$Name' *>> '$logFile'`""
    $action     = New-ScheduledTaskAction -Execute 'pwsh' -Argument $actionArgs

    $trigger = switch -Regex ($Schedule) {
        '^Daily$'     { New-ScheduledTaskTrigger -Daily  -At $At }
        '^Weekly$'    { New-ScheduledTaskTrigger -Weekly -At $At -DaysOfWeek ([System.DayOfWeek](Get-Date).DayOfWeek) }
        '^Hourly$'    { New-ScheduledTaskTrigger -Once -At $At -RepetitionInterval (if ($RepeatInterval -ne [timespan]::Zero) { $RepeatInterval } else { New-TimeSpan -Hours 1 }) }
        '^OnLogon$'   { New-ScheduledTaskTrigger -AtLogOn }
        '^OnStartup$' { New-ScheduledTaskTrigger -AtStartup }
        default       { New-ScheduledTaskTrigger -Daily  -At $At }
    }

    if ($PSCmdlet.ShouldProcess($taskName, 'Register scheduled task')) {
        try {
            $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -StartWhenAvailable
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
            $taskDesc  = if ($Description) { $Description } else { "PSSnips: run snippet '$Name'" }
            $task      = New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings `
                             -Principal $principal -Description $taskDesc
            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force -ErrorAction Stop | Out-Null

            $schedulesFile = Join-Path $script:Home 'schedules.json'
            $schedules = if (Test-Path $schedulesFile) {
                try { @(Get-Content $schedulesFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { @() }
            } else { @() }
            $entry   = [ordered]@{
                name        = $Name
                taskName    = $taskName
                schedule    = $Schedule
                description = $Description
                createdAt   = (Get-Date -Format 'o')
                at          = $At.ToString('o')
            }
            $updated = @($schedules | Where-Object { $_.name -ne $Name }) + @($entry)
            $updated | ConvertTo-Json -Depth 5 | Set-Content $schedulesFile -Encoding UTF8
            script:Out-OK "Scheduled task '$taskName' registered for snippet '$Name' ($Schedule)."
        } catch {
            script:Out-Err "Failed to register scheduled task: $_"
        }
    }
}

function Get-SnipSchedule {
    <#
    .SYNOPSIS
        Lists scheduled tasks for PSSnips snippets.

    .DESCRIPTION
        Reads ~/.pssnips/schedules.json and queries Windows Task Scheduler for the
        current state of each registered PSSnips task. Displays a table showing the
        snippet name, schedule, next run time, last run time, and current state.
        Use -Name to filter results to a specific snippet.

    .PARAMETER Name
        Optional. Filter results to the schedule for a specific snippet.

    .EXAMPLE
        Get-SnipSchedule

        Displays all scheduled PSSnips tasks.

    .EXAMPLE
        Get-SnipSchedule -Name cleanup-logs

        Shows the schedule information for the 'cleanup-logs' snippet.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: SnippetName, Schedule, NextRun, LastRun, State.

    .NOTES
        Requires Windows Task Scheduler access.
        Tasks are registered in the root Task Scheduler folder with a 'PSSnips_' prefix.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [string]$Name = ''
    )
    script:InitEnv
    $schedulesFile = Join-Path $script:Home 'schedules.json'
    if (-not (Test-Path $schedulesFile)) { script:Out-Info 'No schedules found.'; return @() }

    $schedules = try { @(Get-Content $schedulesFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { @() }
    if ($Name) { $schedules = @($schedules | Where-Object { $_.name -eq $Name }) }
    if (-not $schedules -or $schedules.Count -eq 0) { script:Out-Info 'No schedules found.'; return @() }

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($s in $schedules) {
        $nextRun = 'Unknown'; $lastRun = 'Unknown'; $state = 'Unknown'
        try {
            $task = Get-ScheduledTask -TaskName $s.taskName -ErrorAction SilentlyContinue
            if ($task) {
                $info    = $task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
                $state   = $task.State.ToString()
                $nextRun = if ($info.NextRunTime -and $info.NextRunTime -gt [datetime]::MinValue) {
                    $info.NextRunTime | Get-Date -Format 'yyyy-MM-dd HH:mm'
                } else { 'N/A' }
                $lastRun = if ($info.LastRunTime -and $info.LastRunTime -gt [datetime]::MinValue) {
                    $info.LastRunTime | Get-Date -Format 'yyyy-MM-dd HH:mm'
                } else { 'Never' }
            } else { $state = 'Not found' }
        } catch { $state = 'Error' }
        $rows.Add([pscustomobject]@{
            SnippetName = $s.name
            Schedule    = $s.schedule
            NextRun     = $nextRun
            LastRun     = $lastRun
            State       = $state
        })
    }

    $result = $rows.ToArray()
    Write-Host ''
    Write-Host '  PSSnips Scheduled Tasks' -ForegroundColor Cyan
    Write-Host "  $('─' * 78)" -ForegroundColor DarkGray
    Write-Host ("  {0,-22} {1,-12} {2,-18} {3,-18} {4}" -f 'SNIPPET', 'SCHEDULE', 'NEXT RUN', 'LAST RUN', 'STATE') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 78)" -ForegroundColor DarkGray
    foreach ($r in $result) {
        $c = switch ($r.State) {
            'Ready'    { 'Green'    }
            'Disabled' { 'DarkGray' }
            'Running'  { 'Yellow'   }
            default    { 'Gray'     }
        }
        Write-Host ("  {0,-22} {1,-12} {2,-18} {3,-18} {4}" -f $r.SnippetName, $r.Schedule, $r.NextRun, $r.LastRun, $r.State) -ForegroundColor $c
    }
    Write-Host ''
    return $result
}

function Remove-SnipSchedule {
    <#
    .SYNOPSIS
        Removes a scheduled task for a PSSnips snippet.

    .DESCRIPTION
        Unregisters the Windows Scheduled Task associated with the named snippet and
        removes the entry from ~/.pssnips/schedules.json. Prompts for confirmation
        unless -Force is specified.

    .PARAMETER Name
        Mandatory. The name of the snippet whose schedule should be removed.

    .PARAMETER Force
        Optional switch. Skips the confirmation prompt.

    .EXAMPLE
        Remove-SnipSchedule -Name cleanup-logs

        Prompts for confirmation, then removes the schedule for 'cleanup-logs'.

    .EXAMPLE
        Remove-SnipSchedule -Name cleanup-logs -Force

        Removes the schedule without prompting.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation or error message to the host.

    .NOTES
        The scheduled task is unregistered from Windows Task Scheduler.
        The schedules.json entry is also removed.
        If the task is not found in Task Scheduler, the metadata is still removed.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Snippet name whose schedule to remove')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [switch]$Force
    )
    script:InitEnv
    $schedulesFile = Join-Path $script:Home 'schedules.json'
    if (-not (Test-Path $schedulesFile)) {
        Write-Error "No schedule found for '$Name'." -ErrorAction Continue; return
    }
    $schedules = try { @(Get-Content $schedulesFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { @() }
    $entry     = $schedules | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $entry) { Write-Error "No schedule found for snippet '$Name'." -ErrorAction Continue; return }

    if (-not $Force) {
        $yn = Read-Host "  Remove schedule for '$Name'? [y/N]"
        if ($yn -notin 'y', 'Y') { script:Out-Info 'Cancelled.'; return }
    }

    if ($Force -or $PSCmdlet.ShouldProcess($entry.taskName, 'Unregister scheduled task')) {
        try {
            $task = Get-ScheduledTask -TaskName $entry.taskName -ErrorAction SilentlyContinue
            if ($task) { Unregister-ScheduledTask -TaskName $entry.taskName -Confirm:$false -ErrorAction Stop }
        } catch {
            script:Out-Warn "Could not unregister task '$($entry.taskName)': $_"
        }
        $updated = @($schedules | Where-Object { $_.name -ne $Name })
        if ($updated.Count -gt 0) {
            $updated | ConvertTo-Json -Depth 5 | Set-Content $schedulesFile -Encoding UTF8
        } else {
            Remove-Item $schedulesFile -Force -ErrorAction SilentlyContinue
        }
        script:Out-OK "Schedule for '$Name' removed."
    }
}

function Initialize-SnipPreCommitHook {
    <#
    .SYNOPSIS
        Installs a PSSnips pre-commit hook in a Git repository.

    .DESCRIPTION
        Installs a git pre-commit hook at <RepoPath>/.git/hooks/pre-commit that
        finds all staged .ps1 files and runs Test-Snip on each one. If a pre-commit
        hook already exists, the PSSnips check is appended rather than replacing it.
        A guard comment prevents duplicate insertions on repeated calls.
        Supports -WhatIf to preview changes without writing any files.

    .PARAMETER RepoPath
        Optional. Path to the Git repository root. Defaults to the current directory.

    .EXAMPLE
        Initialize-SnipPreCommitHook

        Installs the pre-commit hook in the current directory's Git repository.

    .EXAMPLE
        Initialize-SnipPreCommitHook -RepoPath 'C:\MyProject'

        Installs the hook in the specified repository.

    .EXAMPLE
        Initialize-SnipPreCommitHook -WhatIf

        Previews the hook that would be installed without making any changes.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation or error message to the host.

    .NOTES
        The hook uses POSIX shell syntax (#!/bin/sh) for compatibility with Git for
        Windows. On Windows, Git's bundled sh.exe executes the hook at commit time.
        If a hook already exists, the PSSnips block is appended and guarded with a
        comment marker to prevent duplicate insertions on repeated calls.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$RepoPath = (Get-Location).Path
    )
    script:InitEnv

    $gitDir   = Join-Path $RepoPath '.git'
    $hooksDir = Join-Path $gitDir 'hooks'
    $hookFile = Join-Path $hooksDir 'pre-commit'

    if (-not (Test-Path $gitDir)) {
        Write-Error "No .git directory found at '$RepoPath'. Is this a Git repository?" -ErrorAction Continue
        return
    }

    if ($PSCmdlet.ShouldProcess($hookFile, 'Install PSSnips pre-commit hook')) {
        try {
            if (-not (Test-Path $hooksDir)) {
                New-Item -ItemType Directory -Path $hooksDir -Force | Out-Null
            }

            if (Test-Path $hookFile) {
                $existing = Get-Content $hookFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($existing -match 'pssnips-precommit-v1') {
                    script:Out-Info 'PSSnips pre-commit hook already installed.'
                    return
                }
                # Append to existing hook
                $pssnipsBlock = "`n# pssnips-precommit-v1`n" +
                    "staged_ps1=`$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.ps1$')`n" +
                    "if [ -n `"`$staged_ps1`" ]; then`n" +
                    "    for f in `$staged_ps1; do`n" +
                    "        snip_name=`$(basename `"`$f`" .ps1)`n" +
                    "        pwsh -NonInteractive -Command `"Import-Module PSSnips -ErrorAction Stop; `$r = Test-Snip -Name '`$snip_name' -PassThru; if (`$r | Where-Object { `$_.Severity -eq 'Error' }) { exit 1 }`" 2>/dev/null`n" +
                    "        if [ `$? -ne 0 ]; then echo `"[PSSnips] Lint errors in `$f - commit blocked.`" >&2; exit 1; fi`n" +
                    "    done`n" +
                    "fi`n"
                Add-Content -Path $hookFile -Value $pssnipsBlock -Encoding UTF8
                script:Out-OK "PSSnips pre-commit check appended to existing hook: $hookFile"
            } else {
                $newHook = "#!/bin/sh`n" +
                    "# pssnips-precommit-v1`n" +
                    "staged_ps1=`$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null | grep '\.ps1$')`n" +
                    "if [ -n `"`$staged_ps1`" ]; then`n" +
                    "    for f in `$staged_ps1; do`n" +
                    "        snip_name=`$(basename `"`$f`" .ps1)`n" +
                    "        pwsh -NonInteractive -Command `"Import-Module PSSnips -ErrorAction Stop; `$r = Test-Snip -Name '`$snip_name' -PassThru; if (`$r | Where-Object { `$_.Severity -eq 'Error' }) { exit 1 }`" 2>/dev/null`n" +
                    "        if [ `$? -ne 0 ]; then echo `"[PSSnips] Lint errors in `$f - commit blocked.`" >&2; exit 1; fi`n" +
                    "    done`n" +
                    "fi`n"
                Set-Content -Path $hookFile -Value $newHook -Encoding UTF8 -NoNewline
                script:Out-OK "PSSnips pre-commit hook installed: $hookFile"
            }
        } catch {
            script:Out-Err "Failed to install pre-commit hook: $_"
        }
    }
}

function Sync-SnipMetadata {
    <#
    .SYNOPSIS
        Synchronises snippet index metadata from PowerShell comment-based help (CBH).

    .DESCRIPTION
        Scans local .ps1 and .psm1 snippets for block-comment CBH and updates the
        index with values extracted from .SYNOPSIS (→ description) and .NOTES Tags:
        (→ tags). By default only empty fields are filled. Use -Overwrite to replace
        existing values. Use -WhatIf to preview changes without applying them.

        This eliminates the need to maintain the same information in both the snippet
        file's CBH block and the PSSnips index entry — the CBH becomes the authoritative
        source for PowerShell snippet metadata.

    .PARAMETER Name
        Optional. The name of a single snippet to sync. Omit to scan all .ps1/.psm1
        snippets.

    .PARAMETER Overwrite
        Optional switch. When set, overwrites existing description and tags with CBH
        values even when they are already populated. Default: fills empty fields only.

    .EXAMPLE
        Sync-SnipMetadata

        Scans all PS1/PSM1 snippets and auto-fills any empty description or tags from CBH.

    .EXAMPLE
        Sync-SnipMetadata -Overwrite

        Overwrites all description and tag fields with values extracted from CBH.

    .EXAMPLE
        Sync-SnipMetadata -Name deploy-script -WhatIf

        Previews what would be updated for the 'deploy-script' snippet without applying.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a per-snippet summary and a final count to the host.

    .NOTES
        Only block-comment CBH (angle-bracket hash ... hash angle-bracket) is parsed.
        Tags are read from a "Tags: value1, value2" line inside the .NOTES keyword section.
        Snippets without a CBH block, or whose CBH yields no usable fields, are skipped.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position=0)][string]$Name,
        [switch]$Overwrite
    )
    script:InitEnv
    $idx = script:LoadIdx

    $targets = if ($Name) {
        if (-not $idx.snippets.ContainsKey($Name)) {
            Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return
        }
        @($Name)
    } else {
        @($idx.snippets.Keys | Where-Object {
            $idx.snippets[$_].Language -in 'ps1','psm1'
        })
    }

    $updated = 0; $skipped = 0
    foreach ($n in $targets) {
        $filePath = script:FindFile -Name $n
        if (-not $filePath -or -not (Test-Path $filePath)) { $skipped++; continue }
        $ext = [System.IO.Path]::GetExtension($filePath).TrimStart('.').ToLower()
        if ($ext -notin 'ps1','psm1') { $skipped++; continue }

        $content = Get-Content $filePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $content) { $skipped++; continue }

        $cbh = script:ParseCBH -Content $content
        if (-not $cbh.Synopsis -and $cbh.Tags.Count -eq 0) { $skipped++; continue }

        $entry        = $idx.snippets[$n]
        $descChanged  = $false
        $tagsChanged  = $false

        if ($cbh.Synopsis) {
            $emptyDesc = -not $entry.Description
            if ($emptyDesc -or $Overwrite) {
                if ($PSCmdlet.ShouldProcess($n, "Set description to '$($cbh.Synopsis)'")) {
                    $entry.Description = $cbh.Synopsis
                    $descChanged = $true
                }
            }
        }

        if ($cbh.Tags.Count -gt 0) {
            $emptyTags = @($entry.Tags).Count -eq 0
            if ($emptyTags -or $Overwrite) {
                if ($PSCmdlet.ShouldProcess($n, "Set tags to [$($cbh.Tags -join ', ')]")) {
                    $entry.Tags = $cbh.Tags
                    $tagsChanged = $true
                }
            }
        }

        if ($descChanged -or $tagsChanged) {
            $updated++
            $parts = @()
            if ($descChanged) { $parts += "description='$($cbh.Synopsis)'" }
            if ($tagsChanged) { $parts += "tags=[$($cbh.Tags -join ', ')]" }
            script:Out-OK "  $n — $($parts -join ', ')"
        } else {
            $skipped++
        }
    }

    if ($updated -gt 0 -and -not $WhatIfPreference) { script:SaveIdx -Idx $idx }
    script:Out-Info "Sync complete — $updated updated, $skipped skipped."
}

function Register-SnipEvent {
    <#
    .SYNOPSIS
        Registers a script block handler for a PSSnips lifecycle event.

    .DESCRIPTION
        Attaches a script block to a named PSSnips lifecycle event. The handler
        is invoked automatically whenever the event is raised by the module.
        Multiple handlers can be registered for the same event; each receives a
        hashtable $Data argument with event-specific fields.

        Supported events and their $Data keys:
          SnipCreated   — Name, Language, Description, Tags
          SnipEdited    — Name, FilePath
          SnipDeleted   — Name
          SnipExecuted  — Name, Language, Duration (seconds as [double])
          SnipPublished — Name, Provider (github|gitlab|bitbucket), Url

        Register handlers in your $PROFILE to persist across sessions.

    .PARAMETER EventName
        Mandatory. The name of the event to subscribe to. Must be one of:
        SnipCreated, SnipEdited, SnipDeleted, SnipExecuted, SnipPublished.

    .PARAMETER Handler
        Mandatory. A script block that accepts a single [hashtable] parameter.

    .PARAMETER Id
        Optional. A unique identifier for this handler registration. Defaults to
        a new GUID. Use a stable Id in $PROFILE registrations so that re-sourcing
        the profile does not create duplicate handlers.

    .EXAMPLE
        Register-SnipEvent -Event SnipExecuted -Handler {
            param($e)
            "[$(Get-Date -f 'HH:mm:ss')] Ran '$($e.Name)' in $($e.Duration)s" |
                Add-Content ~/.pssnips/perf.log
        }

        Logs execution time for every snippet run.

    .EXAMPLE
        Register-SnipEvent -Event SnipCreated -Id 'my-slack-hook' -Handler {
            param($e)
            $body = @{ text = "New snippet: $($e.Name) [$($e.Language)]" } | ConvertTo-Json
            Invoke-RestMethod https://hooks.slack.com/... -Method Post -Body $body -ContentType 'application/json'
        }

        Posts a Slack notification whenever a snippet is created.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String
        Returns the registration Id (useful for later Unregister-SnipEvent calls).

    .NOTES
        Handlers run synchronously in the caller's thread. Keep handlers fast;
        long-running operations should use Start-Job or runspaces internally.
        Handler errors are caught and written to Verbose — they never propagate
        to the caller.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, HelpMessage = 'Event name to subscribe to')]
        [ValidateSet('SnipCreated','SnipEdited','SnipDeleted','SnipExecuted','SnipPublished')]
        [string]$EventName,

        [Parameter(Mandatory, HelpMessage = 'Script block handler — receives a [hashtable] $Data argument')]
        [scriptblock]$Handler,

        [string]$Id = ([guid]::NewGuid().ToString())
    )
    if (-not $script:EventRegistry.ContainsKey($EventName)) {
        $script:EventRegistry[$EventName] = @{}
    }
    $script:EventRegistry[$EventName][$Id] = $Handler
    return $Id
}

function Unregister-SnipEvent {
    <#
    .SYNOPSIS
        Removes a previously registered PSSnips event handler.

    .DESCRIPTION
        Removes the handler identified by -Id from the named event's registry.
        Use the Id returned by Register-SnipEvent (or the stable Id you supplied)
        to target the specific registration. If the Id is not found the function
        returns silently.

    .PARAMETER EventName
        Mandatory. The event name whose handler should be removed.

    .PARAMETER Id
        Mandatory. The registration Id returned by Register-SnipEvent, or the
        stable Id supplied when the handler was registered.

    .EXAMPLE
        $regId = Register-SnipEvent -Event SnipCreated -Handler { param($e) Write-Host $e.Name }
        Unregister-SnipEvent -Event SnipCreated -Id $regId

        Registers then immediately removes a handler.

    .INPUTS
        None.

    .OUTPUTS
        None.

    .NOTES
        Removing a non-existent Id is a silent no-op.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions',
        '', Justification = 'Modifies in-memory event registry only; no persistent state change.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, HelpMessage = 'Event name')]
        [ValidateSet('SnipCreated','SnipEdited','SnipDeleted','SnipExecuted','SnipPublished')]
        [string]$EventName,

        [Parameter(Mandatory, HelpMessage = 'Registration Id to remove')]
        [string]$Id
    )
    if ($script:EventRegistry.ContainsKey($EventName)) {
        $script:EventRegistry[$EventName].Remove($Id)
    }
}

