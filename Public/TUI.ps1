# PSSnips — Interactive terminal UI (Start-SnipManager).
# Full-screen terminal UI (TUI) built on raw console key input.
# Uses [Console]::SetCursorPosition for in-place screen redraws and
# $Host.UI.RawUI.ReadKey for single-keypress navigation without Enter.

function Start-SnipManager {
    <#
    .SYNOPSIS
        Launches the full-screen interactive terminal snippet manager (TUI).

    .DESCRIPTION
        Starts a full-screen text UI that displays a navigable list of snippets with
        real-time search filtering. The UI is drawn using [Console]::SetCursorPosition
        for in-place redraws without flickering. Navigation uses raw virtual key codes
        read via $Host.UI.RawUI.ReadKey:
          VK 38 (Up arrow)    - move selection up
          VK 40 (Down arrow)  - move selection down
          VK 13 (Enter)       - open detail view
          VK 39 (Right arrow) - open detail view
          VK 27 (Esc)         - return to list view from detail
          VK 37 (Left arrow)  - return to list view from detail
        Single-character commands (n, e, r, c, d, g, /) are handled in the default
        branch of the key switch. The cursor is hidden during TUI operation and
        restored in a finally block to ensure visibility is not lost on error.

    .EXAMPLE
        Start-SnipManager

        Launches the interactive TUI snippet manager.

    .EXAMPLE
        snip

        Equivalent shortcut: calling snip with no arguments starts the TUI.

    .INPUTS
        None.

    .OUTPUTS
        None. All interaction is through the console.

    .NOTES
        Requires an interactive host with RawUI support. Will not work correctly
        in non-interactive sessions (e.g., CI pipelines) or when stdout is
        redirected. The TUI shows up to 20 snippets per page; use [/] to filter
        when the collection exceeds 20 items.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Start-SnipManager launches a read-only interactive TUI and does not change system state directly.')]
    param()
    script:InitEnv

    $idx   = script:LoadIdx
    $sel   = 0
    $mode  = 'list'   # 'list' | 'detail'
    $query = ''
    $msg   = ''

    function Get-Filtered {
        param([hashtable]$Idx, [string]$q)
        $allItems = @(foreach ($n in ($Idx.snippets.Keys | Sort-Object)) {
            $m = $Idx.snippets[$n]
            if (-not $q -or $n -like "*$q*" -or ($m.Description -like "*$q*") -or
                (($m.Tags -join ',') -like "*$q*")) {
                [pscustomobject]@{ Name = $n; Meta = $m; Pinned = $m.Pinned }
            }
        })
        # Pinned snippets float to the top
        $pinnedItems    = @($allItems | Where-Object { $_.Pinned })
        $unpinnedItems  = @($allItems | Where-Object { -not $_.Pinned })
        return @($pinnedItems) + @($unpinnedItems)
    }

    function Write-SnipList {
        param([array]$list, [int]$s, [string]$q, [string]$statusMsg)
        [Console]::SetCursorPosition(0,0)
        script:Out-Banner
        Write-Host ("  {0,-6} {1,-5} {2}" -f 'Keys','','Actions') -ForegroundColor DarkGray
        Write-Host "  [↑↓] Navigate  [Enter/→] View  [n] New  [e] Edit  [r] Run  [c] Copy  [d] Delete" -ForegroundColor DarkGray
        Write-Host "  [g] Export Gist  [/] Search  [q] Quit" -ForegroundColor DarkGray
        if ($q) { Write-Host ("  Filter: {0,-40}" -f $q) -ForegroundColor Yellow } else { Write-Host "  $(' ' * 50)" }
        Write-Host "  $('─' * 76)" -ForegroundColor DarkGray

        if ($list.Count -eq 0) {
            Write-Host "  (no snippets — press [n] to create one)$(' ' * 20)" -ForegroundColor DarkGray
        } else {
            $visible = [Math]::Min($list.Count, 20)
            for ($i = 0; $i -lt $visible; $i++) {
                $item  = $list[$i]
                $c     = script:LangColor -ext $item.Meta.language
                $gmark = if ($item.Meta.gistId) { ' [G]' } else { '    ' }
                $desc  = if ($item.Meta.description) { "  $($item.Meta.description)" } else { '' }
                $tags  = if (@($item.Meta.tags).Count -gt 0) { "  [$( (@($item.Meta.tags) -join ',') )]" } else { '' }
                $pin   = if ($item.Pinned) { '★ ' } else { '  ' }
                $row   = "{0}{1,-24} {2,-6}{3}{4}{5}" -f $pin, $item.Name, $item.Meta.language, $gmark, $desc, $tags
                if ($row.Length -gt 74) { $row = $row.Substring(0,71) + '...' }
                if ($i -eq $s) {
                    Write-Host ("  ► {0,-74}" -f $row) -BackgroundColor DarkBlue -ForegroundColor White
                } else {
                    Write-Host ("    " + $row + (' ' * [Math]::Max(0, 74 - $row.Length))) -ForegroundColor $c
                }
            }
            if ($list.Count -gt 20) { Write-Host "  ... and $($list.Count - 20) more. Use [/] to filter." -ForegroundColor DarkGray }
        }
        Write-Host "  $('─' * 76)" -ForegroundColor DarkGray
        if ($statusMsg) { Write-Host ("  {0,-76}" -f $statusMsg) -ForegroundColor Green } else { Write-Host (' ' * 80) }
        Write-Host "" 
    }

    function Write-SnipDetail {
        param([pscustomobject]$item)
        [Console]::SetCursorPosition(0,0)
        $c    = script:LangColor -ext $item.Meta.language
        $path = script:FindFile -Name $item.Name
        Write-Host ""
        Write-Host ("  ╔═ {0} ({1}) ═╗" -f $item.Name, $item.Meta.language) -ForegroundColor $c
        if ($item.Meta.description) { Write-Host "  $($item.Meta.description)" -ForegroundColor Gray }
        if ($item.Meta.gistUrl)     { Write-Host "  Gist: $($item.Meta.gistUrl)" -ForegroundColor DarkCyan }
        if (@($item.Meta.tags).Count -gt 0) { Write-Host "  Tags: $( (@($item.Meta.tags) -join ', '))" -ForegroundColor DarkGray }
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        if ($path -and (Test-Path $path)) {
            $lines = Get-Content $path -Encoding UTF8
            $shown = [Math]::Min($lines.Count, 30)
            for ($i = 0; $i -lt $shown; $i++) { Write-Host "  $($lines[$i])" }
            if ($lines.Count -gt 30) { Write-Host "  ... ($($lines.Count - 30) more lines)" -ForegroundColor DarkGray }
        }
        Write-Host "  $('─' * 60)" -ForegroundColor DarkGray
        Write-Host "  [e] Edit  [r] Run  [c] Copy  [g] Gist  [Esc/←] Back" -ForegroundColor DarkGray
        Write-Host (' ' * 80)
    }

    try {
        [Console]::CursorVisible = $false
        Clear-Host

        :outer while ($true) {
            $list = Get-Filtered -Idx $idx -q $query
        if ($null -eq $list) { $list = @() }
            if ($sel -ge $list.Count) { $sel = [Math]::Max(0, $list.Count - 1) }

            switch ($mode) {
                'list'   { Write-SnipList   -list $list -s $sel -q $query -statusMsg $msg }
                'detail' { if ($list.Count -gt 0) { Clear-Host; Write-SnipDetail -item $list[$sel] } else { $mode = 'list' } }
            }
            $msg = ''

            $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $vk  = $key.VirtualKeyCode
            $ch  = $key.Character

            if ($mode -eq 'list') {
                switch ($vk) {
                    38 { if ($sel -gt 0) { $sel-- } }                       # Up
                    40 { if ($sel -lt $list.Count - 1) { $sel++ } }          # Down
                    { $_ -in 13,39 } { if ($list.Count -gt 0) { $mode = 'detail' } } # Enter / Right
                    default {
                        switch ($ch) {
                            'q' { break outer }
                            'n' {
                                [Console]::CursorVisible = $true
                                Clear-Host
                                $nm = Read-Host "  New snippet name"
                                $la = Read-Host "  Language [$( (script:LoadCfg).DefaultLanguage )]"
                                $de = Read-Host "  Description (optional)"
                                [Console]::CursorVisible = $false
                                if ($nm) {
                                    if (-not $la) { $la = (script:LoadCfg).DefaultLanguage }
                                    New-Snip -Name $nm -Language $la -Description $de
                                    $idx = script:LoadIdx
                                    $msg = "[+] Created '$nm'"
                                }
                                Clear-Host
                            }
                            'e' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    Clear-Host; Edit-Snip -Name $list[$sel].Name
                                    $idx = script:LoadIdx
                                    $msg = "[+] Saved changes to '$($list[$sel].Name)'"
                                    [Console]::CursorVisible = $false; Clear-Host
                                }
                            }
                            'r' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    Clear-Host; Invoke-Snip -Name $list[$sel].Name
                                    Read-Host "`n  [Press Enter to return]"
                                    [Console]::CursorVisible = $false; Clear-Host
                                }
                            }
                            'c' {
                                if ($list.Count -gt 0) { Copy-Snip -Name $list[$sel].Name; $msg = "[+] Copied to clipboard" }
                            }
                            'd' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    $yn = Read-Host "  Delete '$($list[$sel].Name)'? [y/N]"
                                    [Console]::CursorVisible = $false
                                    if ($yn -in 'y','Y') {
                                        Remove-Snip -Name $list[$sel].Name -Force
                                        $idx = script:LoadIdx
                                        if ($sel -ge $list.Count - 1 -and $sel -gt 0) { $sel-- }
                                        $msg = "[+] Deleted"
                                    }
                                    Clear-Host
                                }
                            }
                            'g' {
                                if ($list.Count -gt 0) {
                                    [Console]::CursorVisible = $true
                                    Clear-Host; Export-Gist -Name $list[$sel].Name
                                    $idx = script:LoadIdx
                                    Read-Host "`n  [Press Enter to return]"
                                    [Console]::CursorVisible = $false; Clear-Host
                                }
                            }
                            '/' {
                                [Console]::CursorVisible = $true
                                $query = Read-Host "  Search"
                                [Console]::CursorVisible = $false
                                $sel = 0; Clear-Host
                            }
                        }
                    }
                }
            } else {
                # detail mode
                switch ($vk) {
                    { $_ -in 8,27,37 } { $mode = 'list'; Clear-Host }   # Backspace / Esc / Left
                    default {
                        switch ($ch) {
                            'e' {
                                [Console]::CursorVisible = $true
                                Clear-Host; Edit-Snip -Name $list[$sel].Name
                                $idx = script:LoadIdx
                                [Console]::CursorVisible = $false; Clear-Host
                            }
                            'r' {
                                [Console]::CursorVisible = $true
                                Clear-Host; Invoke-Snip -Name $list[$sel].Name
                                Read-Host "`n  [Press Enter to return]"
                                [Console]::CursorVisible = $false; Clear-Host
                            }
                            'c' { Copy-Snip -Name $list[$sel].Name }
                            'g' {
                                [Console]::CursorVisible = $true
                                Clear-Host; Export-Gist -Name $list[$sel].Name
                                $idx = script:LoadIdx
                                Read-Host "`n  [Press Enter to return]"
                                [Console]::CursorVisible = $false; Clear-Host
                            }
                        }
                    }
                }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        Clear-Host
    }
}

