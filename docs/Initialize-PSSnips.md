---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Initialize-PSSnips

## SYNOPSIS
Initializes the PSSnips data directory and writes the default configuration.

## SYNTAX

```
Initialize-PSSnips [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Creates the ~/.pssnips directory and its snippets subdirectory if they do not
exist.
Writes a default config.json and an empty index.json when those files
are absent.
Displays the detected editor and reminds the user to configure a
GitHub token if Gist features are needed.
This function is called automatically
when the module is imported; calling it manually is useful after a fresh
installation or to repair a missing configuration.

## EXAMPLES

### EXAMPLE 1
```
Initialize-PSSnips
```

Ensures the data directory and config files exist and reports the ready state.

### EXAMPLE 2
```
# Re-initialise after manually deleting the config directory
Remove-Item ~/.pssnips -Recurse -Force
Initialize-PSSnips
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

### None. Writes status messages to the host.
## NOTES
The module calls script:InitEnv automatically on import, so explicit calls to
Initialize-PSSnips are typically not needed in normal usage.
Data directory: ~/.pssnips  (controlled by $script:Home)

## RELATED LINKS
