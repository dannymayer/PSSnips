---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Set-SnipConfig

## SYNOPSIS
Updates one or more PSSnips configuration settings.

## SYNTAX

```
Set-SnipConfig [[-Editor] <String>] [[-GitHubToken] <String>] [[-GitHubUsername] <String>]
 [[-SnippetsDir] <String>] [[-DefaultLanguage] <String>] [[-ConfirmDelete] <Boolean>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Loads the current configuration from ~/.pssnips/config.json, applies any
provided parameter values, and saves the updated configuration back to disk.
Only the parameters you supply are changed; unspecified settings retain their
current values.
Multiple settings can be updated in a single call.

## EXAMPLES

### EXAMPLE 1
```
Set-SnipConfig -Editor nvim
```

Switches the default editor to Neovim.

### EXAMPLE 2
```
Set-SnipConfig -GitHubToken 'ghp_abc123' -GitHubUsername 'octocat'
```

Saves GitHub credentials to enable Gist integration.

### EXAMPLE 3
```
Set-SnipConfig -DefaultLanguage py -ConfirmDelete $false
```

Sets Python as the default language and disables delete confirmation prompts.

## PARAMETERS

### -ConfirmDelete
When $true (the default), Remove-Snip prompts for confirmation before
deleting.
Set to $false to suppress the confirmation prompt globally.
Optional.

```yaml
Type: System.Nullable`1[System.Boolean]
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -DefaultLanguage
The file extension (without dot) used when creating a new snippet without an
explicit -Language parameter (e.g., 'ps1', 'py', 'js').
Optional.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Editor
The command name or path of the preferred text editor (e.g., 'edit', 'nvim',
'code').
Optional.
Falls back through EditorFallbacks if the command is not
found on PATH.

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

### -GitHubToken
A GitHub personal access token (PAT) with the 'gist' scope.
Optional.
Required for all Gist operations.
Can also be supplied via $env:GITHUB_TOKEN.

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

### -GitHubUsername
Your GitHub username.
Optional.
Used to list your own Gists when calling
Get-GistList without specifying -Username.

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

### -SnippetsDir
Absolute path to the directory where snippet files are stored.
Optional.
Defaults to ~/.pssnips/snippets.
The directory is created if it does not exist.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs. The cmdlet is not run.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases: wi

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

### None. Writes a confirmation message to the host on success.
## NOTES
Settings are persisted to ~/.pssnips/config.json as UTF-8 JSON.
GitHub tokens are stored in plain text; consider using $env:GITHUB_TOKEN
as an alternative for improved security.

## RELATED LINKS
