---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# snip

## SYNOPSIS
PSSnips main entry point - dispatches sub-commands or launches the interactive TUI.

## SYNTAX

```
snip [[-Command] <String>] [[-Arg1] <String>] [[-Arg2] <String>] [-Rest <String[]>] [-Language <String>]
 [-Description <String>] [-Tags <String[]>] [-Content <String>] [-Path <String>] [-Editor <String>]
 [-Token <String>] [-Username <String>] [-Public] [-Force] [-Push] [-Clip] [-All]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
The 'snip' function is the primary command-line interface for PSSnips.
When
called with no arguments it launches the full-screen interactive TUI.
With a
sub-command it routes to the appropriate PSSnips function.

Sub-commands:
  (none) / ui / tui  Open the interactive TUI (Start-SnipManager)
  list  \[filter\]     List snippets (Get-Snip)
  new   \<name\>       Create a snippet and open in editor (New-Snip)
  add   \<name\>       Add from -Path file or pipe (Add-Snip)
  show  \<name\>       Display snippet content (Show-Snip)
  edit  \<name\>       Open snippet in editor (Edit-Snip)
  run   \<name\>       Execute snippet (Invoke-Snip)
  rm    \<name\>       Delete snippet (Remove-Snip)
  copy  \<name\>       Copy to clipboard (Copy-Snip)
  tag   \<name\>       Manage tags (Set-SnipTag)
  search \<query\>     Search by name/description/tag (Get-Snip -Filter)
  config             View or update configuration (Get/Set-SnipConfig)
  gist list          List GitHub Gists (Get-GistList)
  gist show  \<id\>    Display a Gist (Get-Gist)
  gist import \<id\>   Import a Gist locally (Import-Gist)
  gist push  \<name\>  Export snippet to GitHub Gist (Export-Gist)
  gist run   \<id\>    Run a Gist without saving (Invoke-Gist)
  gist sync  \<name\>  Sync snippet with its Gist (Sync-Gist)
  help               Display this help

## EXAMPLES

### EXAMPLE 1
```
snip
```

Launches the interactive full-screen TUI snippet manager.

### EXAMPLE 2
```
snip new deploy -Language ps1 -Description 'Deploy to Azure'
```

Creates a new PowerShell snippet named 'deploy' and opens the editor.

### EXAMPLE 3
```
snip add loader -Path .\loader.py
```

Imports loader.py from disk as a snippet named 'loader'.

### EXAMPLE 4
```
snip gist import abc123def456abc123def456abc1234567 -Name handy-script
```

Downloads a GitHub Gist and saves it as local snippet 'handy-script'.

### EXAMPLE 5
```
snip config -Token ghp_abc123
```

Saves a GitHub PAT to the configuration for Gist operations.

## PARAMETERS

### -All
With 'gist import': imports all files from the Gist.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Arg1
First positional argument for the sub-command, typically the snippet name
or the Gist sub-command (list, show, import, push, run, sync).

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Arg2
Second positional argument, typically a Gist ID or file name.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Clip
With 'add': reads content from the Windows clipboard.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Command
The sub-command to execute.
Omit to launch the interactive TUI.
Accepts short aliases: ls, n, a, s, e, r, rm/del, cp/yank, f.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Content
Snippet content string forwarded to New-Snip (bypasses editor).

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Description
Short description for new or exported snippets.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Editor
Editor command override forwarded to New-Snip or Edit-Snip.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Force
Skips confirmation prompts (forwarded to Remove-Snip or Add-Snip).

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Language
Language/extension override (ps1, py, js, bat, sh, rb, go, ...).
Forwarded to New-Snip, Add-Snip, or Set-SnipConfig as appropriate.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Path
Source file path forwarded to Add-Snip -Path.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: System.Management.Automation.ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Public
Creates a public GitHub Gist (forwarded to Export-Gist).

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Push
With 'gist sync': pushes local content to GitHub instead of pulling.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Rest
{{ Fill Rest Description }}

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -Tags
Array of tag strings for new snippets or tag operations.

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -Token
GitHub personal access token forwarded to Set-SnipConfig -GitHubToken.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Username
GitHub username forwarded to Set-SnipConfig -GitHubUsername.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### Variable. Depends on the sub-command. Most commands write to the host;
### list and search commands also return PSCustomObject arrays.
## NOTES
Calling 'snip \<name\>' where \<name\> matches an existing snippet calls
Show-Snip directly, making snippet names first-class sub-commands.
Short aliases are resolved via regex matching in the internal switch statement.

## RELATED LINKS
