---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Import-Gist

## SYNOPSIS
Downloads a GitHub Gist and saves it as one or more local snippets.

## SYNTAX

```
Import-Gist [-GistId] <String> [-Name <String>] [-FileName <String>] [-All] [-Force]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Fetches the specified Gist from GitHub and writes each selected file to the
configured SnippetsDir.
The snippet language is inferred from the file
extension.
Multi-file Gists prompt interactively for which file to import
unless -All is specified.
If a snippet with the derived name already exists,
a numeric suffix is appended to avoid collision (unless -Force is used).
The Gist ID and URL are stored in the snippet's index metadata to enable
future sync operations.

## EXAMPLES

### EXAMPLE 1
```
Import-Gist abc123def456abc123def456abc1234567
```

Imports the first (or only) file from the Gist as a local snippet.

### EXAMPLE 2
```
Import-Gist abc123def456abc123def456abc1234567 -Name my-local-name
```

Imports the Gist and saves it with the local name 'my-local-name'.

### EXAMPLE 3
```
Import-Gist abc123def456abc123def456abc1234567 -All
```

Imports every file in the Gist as individual snippets.

## PARAMETERS

### -All
Optional switch.
Imports all files from the Gist as separate snippets.

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

### -FileName
Optional.
Imports only the specified file from a multi-file Gist.

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
Optional switch.
Overwrites existing snippets with the same name.

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

### -GistId
Mandatory.
The GitHub Gist ID to import.

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

### -Name
Optional.
Override the local snippet name.
Only applies when importing a
single file; ignored when -All is used.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### None. Writes a confirmation message per imported snippet.
## NOTES
When -Name is not supplied, the snippet name is derived from the Gist
file name (without extension).
For multi-file imports with -All, each file
is stored using its original file base name.

## RELATED LINKS
