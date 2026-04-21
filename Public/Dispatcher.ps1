# PSSnips — Invoke-SnipCLI dispatcher and snip alias.
# The 'snip' function is the primary CLI entry point. It routes sub-commands
# using a regex switch, mapping short aliases (ls, rm, cp, etc.) to the full
# public functions above. Named switches (-Language, -Tags, etc.) are forwarded
# to the appropriate function.

function Invoke-SnipCLI {
    <#
    .SYNOPSIS
        PSSnips main entry point (Invoke-SnipCLI, alias: snip) — dispatches sub-commands or launches the interactive TUI.

    .DESCRIPTION
        Invoke-SnipCLI (invoked via the 'snip' alias) is the primary command-line interface
        for PSSnips. When called with no arguments it launches the full-screen interactive TUI.
        With a sub-command it routes to the appropriate PSSnips function.

        Sub-commands:
          (none) / ui / tui  Open the interactive TUI (Start-SnipManager)
          list  [filter]     List snippets (Get-Snip)
          new   <name>       Create a snippet and open in editor (New-Snip)
          add   <name>       Add from -Path file or pipe (Add-Snip)
          show  <name>       Display snippet content (Show-Snip)
          edit  <name>       Open snippet in editor (Edit-Snip)
          run   <name>       Execute snippet (Invoke-Snip)
          rm    <name>       Delete snippet (Remove-Snip)
          copy  <name>       Copy to clipboard (Copy-Snip)
          tag   <name>       Manage tags (Set-SnipTag)
          search <query>     Search by name/description/tag (Get-Snip -Filter)
          config             View or update configuration (Get/Set-SnipConfig)
          gist list          List GitHub Gists (Get-GistList)
          gist show  <id>    Display a Gist (Get-Gist)
          gist import <id>   Import a Gist locally (Import-Gist)
          gist push  <name>  Export snippet to GitHub Gist (Export-Gist)
          gist run   <id>    Run a Gist without saving (Invoke-Gist)
          gist sync  <name>  Sync snippet with its Gist (Sync-Gist)
          help               Display this help

    .PARAMETER Command
        The sub-command to execute. Omit to launch the interactive TUI.
        Accepts short aliases: ls, n, a, s, e, r, rm/del, cp/yank, f.

    .PARAMETER Arg1
        First positional argument for the sub-command, typically the snippet name
        or the Gist sub-command (list, show, import, push, run, sync).

    .PARAMETER Arg2
        Second positional argument, typically a Gist ID or file name.

    .PARAMETER Language
        Language/extension override (ps1, py, js, bat, sh, rb, go, ...).
        Forwarded to New-Snip, Add-Snip, or Set-SnipConfig as appropriate.

    .PARAMETER Description
        Short description for new or exported snippets.

    .PARAMETER Tags
        Array of tag strings for new snippets or tag operations.

    .PARAMETER Content
        Snippet content string forwarded to New-Snip (bypasses editor).

    .PARAMETER Path
        Source file path forwarded to Add-Snip -Path.

    .PARAMETER Editor
        Editor command override forwarded to New-Snip or Edit-Snip.

    .PARAMETER Token
        GitHub personal access token forwarded to Set-SnipConfig -GitHubToken.

    .PARAMETER Username
        GitHub username forwarded to Set-SnipConfig -GitHubUsername.

    .PARAMETER Public
        Creates a public GitHub Gist (forwarded to Export-Gist).

    .PARAMETER Force
        Skips confirmation prompts (forwarded to Remove-Snip or Add-Snip).

    .PARAMETER Push
        With 'gist sync': pushes local content to GitHub instead of pulling.

    .PARAMETER Clip
        With 'add': reads content from the Windows clipboard.

    .PARAMETER All
        With 'gist import': imports all files from the Gist.

    .EXAMPLE
        snip

        Launches the interactive full-screen TUI snippet manager.

    .EXAMPLE
        snip new deploy -Language ps1 -Description 'Deploy to Azure'

        Creates a new PowerShell snippet named 'deploy' and opens the editor.

    .EXAMPLE
        snip add loader -Path .\loader.py

        Imports loader.py from disk as a snippet named 'loader'.

    .EXAMPLE
        snip gist import abc123def456abc123def456abc1234567 -Name handy-script

        Downloads a GitHub Gist and saves it as local snippet 'handy-script'.

    .EXAMPLE
        snip config -Token ghp_abc123

        Saves a GitHub PAT to the configuration for Gist operations.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        Variable. Depends on the sub-command. Most commands write to the host;
        list and search commands also return PSCustomObject arrays.

    .NOTES
        Calling 'snip <name>' where <name> matches an existing snippet calls
        Show-Snip directly, making snippet names first-class sub-commands.
        Short aliases are resolved via regex matching in the internal switch statement.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]   $Command     = '',
        [Parameter(Position=1)][string]   $Arg1        = '',
        [Parameter(Position=2)][string]   $Arg2        = '',
        [Parameter(ValueFromRemainingArguments)][string[]]$Rest = @(),
        [string]  $Language    = '',
        [string]  $Description = '',
        [string[]]$Tags        = @(),
        [string]  $Content     = '',
        [string]  $Path        = '',
        [string]  $Editor      = '',
        [string]  $Token       = '',
        [string]  $Username    = '',
        [switch]  $Public,
        [switch]  $Force,
        [switch]  $Push,
        [switch]  $Clip,
        [switch]  $All,
        [switch]  $Shared,
        [switch]  $IgnoreDuplicate,
        [string]  $Visibility    = '',
        [string]  $Scope         = ''
    )

    switch -Regex ($Command.ToLower()) {

        '^(|ui|tui)$' { Start-SnipManager }

        '^(list|ls|l)$' {
            $f = if ($Arg1) { $Arg1 } else { '' }
            Get-Snip -Filter $f -Shared:$Shared | Out-Null
        }

        '^(show|cat|view|s)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip show <name>"; return }
            Show-Snip -Name $n
        }

        '^(new|create|n)$' {
            $n = if ($Arg1) { $Arg1 } else { Read-Host "  Snippet name" }
            $l = if ($Language) { $Language } elseif ($Arg2) { $Arg2 } else { '' }
            New-Snip -Name $n -Language $l -Description $Description -Tags $Tags -Content $Content -Editor $Editor -IgnoreDuplicate:$IgnoreDuplicate
        }

        '^(add|a)$' {
            $n = if ($Arg1) { $Arg1 } else { Read-Host "  Snippet name" }
            $p = if ($Path) { $Path } elseif ($Arg2) { $Arg2 } else { '' }
            if ($Clip) {
                Add-Snip -Name $n -FromClipboard -Language $Language -Description $Description -Tags $Tags -Force:$Force -IgnoreDuplicate:$IgnoreDuplicate
            } elseif ($p) {
                Add-Snip -Name $n -Path $p -Language $Language -Description $Description -Tags $Tags -Force:$Force -IgnoreDuplicate:$IgnoreDuplicate
            } else {
                script:Out-Err "Specify -Path <file> or -Clip for clipboard."
            }
        }

        '^(edit|e)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip edit <name>"; return }
            Edit-Snip -Name $n -Editor $Editor
        }

        '^(run|exec|r)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip run <name>"; return }
            Invoke-Snip -Name $n -ArgumentList $Rest
        }

        '^(remove|delete|rm|del)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip rm <name>"; return }
            Remove-Snip -Name $n -Force:$Force
        }

        '^(copy|cp|yank)$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip copy <name>"; return }
            Copy-Snip -Name $n
        }

        '^tag$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip tag <name> -Tags t1,t2"; return }
            Set-SnipTag -Name $n -Tags $Tags -Add @() -Remove @()
        }

        '^(search|find|f)$' {
            $q = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip search <query>"; return }
            Get-Snip -Filter $q | Out-Null
        }

        '^config$' {
            if     ($Token)    { Set-SnipConfig -GitHubToken    $Token    }
            elseif ($Username) { Set-SnipConfig -GitHubUsername $Username }
            elseif ($Editor)   { Set-SnipConfig -Editor         $Editor   }
            elseif ($Language) { Set-SnipConfig -DefaultLanguage $Language }
            else               { Get-SnipConfig }
        }

        '^gist$' {
            $sub = $Arg1.ToLower()
            switch -Regex ($sub) {
                '^(list|ls|)$' {
                    $f = if ($Arg2) { $Arg2 } else { '' }
                    Get-GistList -Filter $f | Out-Null
                }
                '^(show|get|view)$' {
                    $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gist show <id>"; return }
                    Get-Gist -GistId $id
                }
                '^(import|pull|clone)$' {
                    $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gist import <id>"; return }
                    $n  = if ($Rest) { $Rest[0] } else { '' }
                    if ($n) { Import-Gist -GistId $id -Name $n -All:$All }
                    else    { Import-Gist -GistId $id           -All:$All }
                }
                '^(push|export)$' {
                    $n = $Arg2; if (-not $n) { script:Out-Err "Usage: snip gist push <name>"; return }
                    Export-Gist -Name $n -Description $Description -Public:$Public
                }
                '^(run|exec)$' {
                    $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gist run <id>"; return }
                    Invoke-Gist -GistId $id -ArgumentList $Rest
                }
                '^sync$' {
                    $n = $Arg2; if (-not $n) { script:Out-Err "Usage: snip gist sync <name>"; return }
                    Sync-Gist -Name $n -Push:$Push
                }
                default {
                    # bare gist id?
                    if ($Arg1 -match '^[a-f0-9]{20,}$') { Get-Gist -GistId $Arg1 }
                    else { Write-Host "`n  Gist sub-commands: list, show, import, push, run, sync`n" -ForegroundColor DarkCyan }
                }
            }
        }

        '^(pipeline|chain)$' {
            if (-not $Arg1) { script:Out-Err "Usage: snip pipeline <name1,name2,...>"; return }
            $names = ($Arg1 -split ',') + @($Rest | Where-Object { $_ })
            $names = @($names | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $ceFlag = $Force  # reuse -Force switch for -ContinueOnError in pipeline context
            Invoke-Snip -Pipeline $names -ContinueOnError:$ceFlag
        }

        '^gitlab$' {
            $sub = $Arg1.ToLower()
            switch -Regex ($sub) {
                '^(list|ls|)$'    { Get-GitLabSnipList -Filter (if ($Arg2) { $Arg2 } else { '' }) | Out-Null }
                '^(get|show)$'    { $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gitlab get <id>"; return }; Get-GitLabSnip -SnipId $id }
                '^(import|pull)$' { $id = $Arg2; if (-not $id) { script:Out-Err "Usage: snip gitlab import <id>"; return }; Import-GitLabSnip -SnipId $id -Force:$Force }
                '^(export|push)$' { $n = $Arg2; if (-not $n) { script:Out-Err "Usage: snip gitlab export <name>"; return }; $v = if ($Visibility) { $Visibility } else { 'private' }; Export-GitLabSnip -Name $n -Description $Description -Visibility $v }
                default           { Write-Host "`n  GitLab sub-commands: list, get, import, export`n" -ForegroundColor DarkCyan }
            }
        }

        '^gitlab-list$'   { Get-GitLabSnipList -Filter (if ($Arg1) { $Arg1 } else { '' }) | Out-Null }
        '^gitlab-get$'    { $id = $Arg1; if (-not $id) { script:Out-Err "Usage: snip gitlab-get <id>"; return }; Get-GitLabSnip -SnipId $id }
        '^gitlab-import$' { $id = $Arg1; if (-not $id) { script:Out-Err "Usage: snip gitlab-import <id>"; return }; Import-GitLabSnip -SnipId $id -Force:$Force }
        '^gitlab-export$' { $n = $Arg1; if (-not $n) { script:Out-Err "Usage: snip gitlab-export <name>"; return }; $v = if ($Visibility) { $Visibility } else { 'private' }; Export-GitLabSnip -Name $n -Description $Description -Visibility $v }

        '^publish$' {
            $n = if ($Arg1) { $Arg1 } else { script:Out-Err "Usage: snip publish <name>"; return }
            Publish-Snip -Name $n -Force:$Force
        }

        '^sync-shared$' { Sync-SharedSnips -Force:$Force }

        '^install$'   { $s = if ($Scope) { $Scope } else { 'CurrentUserCurrentHost' }; Install-PSSnips -Scope $s -Force:$Force }
        '^uninstall$' { $s = if ($Scope) { $Scope } else { 'CurrentUserCurrentHost' }; Uninstall-PSSnips -Scope $s }

        '^(help|h|\?)$' {
            script:Out-Banner
            Get-Help snip -Full
        }

        default {
            # If command matches a known snippet name, show it
            $idx = script:LoadIdx
            if ($idx.snippets.ContainsKey($Command)) { Show-Snip -Name $Command }
            else { script:Out-Err "Unknown command '$Command'. Run 'snip help' for usage." }
        }
    }
}
Set-Alias -Name snip -Value Invoke-SnipCLI -Scope Global -Description 'PSSnips dispatcher alias'

