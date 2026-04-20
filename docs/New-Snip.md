---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# New-Snip

## SYNOPSIS
Creates a new snippet file and opens it in the configured editor.

## SYNTAX

```
New-Snip [-Name] <String> [[-Language] <String>] [-Description <String>] [-Tags <String[]>] [-Content <String>]
 [-Editor <String>] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Creates a snippet file in the configured snippets directory, registers it in
the index (index.json), and opens the file in the editor unless -Content is
provided.
When -Content is supplied the file is written with that content and
the editor is not launched.
When no -Content is given, a language-appropriate
template is written first.
If a snippet with the same name already exists the
function warns and returns without overwriting.

## EXAMPLES

### EXAMPLE 1
```
New-Snip deploy-script -Language ps1 -Description 'Azure deployment'
```

Creates a new PowerShell snippet and opens it in the default editor.

### EXAMPLE 2
```
New-Snip parser -Language py -Tags @('data', 'util')
```

Creates a Python snippet tagged 'data' and 'util'.

### EXAMPLE 3
```
New-Snip hello -Content 'Write-Host "Hello, World!"'
```

Creates a snippet with pre-filled content without opening an editor.

## PARAMETERS

### -Content
Optional.
If provided, this string is written directly to the snippet file
and the editor is not launched.
Useful for programmatic creation.

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
Optional.
A short human-readable description stored in the index and
shown in Get-Snip listings.

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
Optional.
Overrides the configured editor for this single invocation
(e.g., 'code' to open in VS Code).

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

### -Language
Optional.
The file extension (without dot) that determines the snippet's
language and runner (e.g., 'ps1', 'py', 'js', 'bat', 'sh', 'rb', 'go').
Defaults to the configured DefaultLanguage (ps1 out of the box).

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

### -Name
Mandatory.
A short identifier for the snippet (no spaces, no extension).
Used as both the file base name and the index key.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
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

### -Tags
Optional.
An array of tag strings to categorise the snippet
(e.g., @('devops', 'azure')).

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

### None. Writes a success or warning message to the host.
## NOTES
Template files for ps1, py, js, ts, bat, sh, rb, and go are automatically
populated with the snippet name and description as header comments.
The editor is determined by script:GetEditor which walks the configured
Editor then EditorFallbacks list.

## RELATED LINKS
