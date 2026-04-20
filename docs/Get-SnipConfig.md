---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-SnipConfig

## SYNOPSIS
Shows the current PSSnips configuration settings.

## SYNTAX

```
Get-SnipConfig [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads and displays all settings from the PSSnips config.json file located in
the ~/.pssnips directory.
Settings include the editor command, GitHub token
and username, snippet storage path, default language, and delete confirmation
preference.
GitHub tokens are masked in the output, showing only the last
four characters.

## EXAMPLES

### EXAMPLE 1
```
Get-SnipConfig
```

Displays the full configuration table in the terminal.

### EXAMPLE 2
```
# Check which editor is configured before editing a snippet
Get-SnipConfig
Edit-Snip my-deploy-script
```

## PARAMETERS

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### None. Output is written directly to the host (formatted table).
## NOTES
Configuration is stored as JSON at ~/.pssnips/config.json.
Use Set-SnipConfig to change individual settings.

## RELATED LINKS
