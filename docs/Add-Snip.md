---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Add-Snip

## SYNOPSIS
Adds a new snippet from an existing file or pipeline input.

## SYNTAX

### File (Default)
```
Add-Snip [-Name] <String> [[-Path] <String>] [-Language <String>] [-Description <String>] [-Tags <String[]>]
 [-Force] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Pipe
```
Add-Snip [-Name] <String> [-InputObject <String[]>] [-Language <String>] [-Description <String>]
 [-Tags <String[]>] [-Force] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Imports content into PSSnips from two sources:
  File     - reads a file from disk via -Path.
The language is inferred from
             the source file's extension when -Language is not specified.
  Pipeline - collects lines piped into the function and joins them with
             newlines.
Requires -Language when the extension cannot be
             inferred from context.
The snippet file is written to the configured SnippetsDir and registered in
the index.
Use -Force to overwrite an existing snippet with the same name.

## EXAMPLES

### EXAMPLE 1
```
Add-Snip my-script -Path .\deploy.ps1
```

Imports deploy.ps1 as a snippet named 'my-script'.

### EXAMPLE 2
```
Get-Content .\parser.py | Add-Snip parser -Language py
```

Pipes a Python file's contents into a new snippet named 'parser'.

## PARAMETERS

### -Description
Optional.
Short description stored in the index.

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
Overwrites an existing snippet with the same name without
prompting.

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

### -InputObject
Optional (Pipe parameter set).
Accepts string lines from the pipeline.
All lines are collected and joined before saving.

```yaml
Type: System.String[]
Parameter Sets: Pipe
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -Language
Optional.
Overrides the inferred or default language/extension.

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

### -Name
Mandatory.
The identifier for the new snippet (no spaces, no extension).

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

### -Path
Optional (File parameter set).
Path to the source file to import.
The language is derived from the file extension when -Language is omitted.

```yaml
Type: System.String
Parameter Sets: File
Aliases:

Required: False
Position: 2
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
Array of tag strings for the snippet.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]
### Accepts string lines via the pipeline when using the Pipe parameter set.
## OUTPUTS

### None. Writes a confirmation message to the host.
## NOTES
The Pipe parameter set collects all input in the process block and writes
the snippet only in the end block after the pipeline has been fully read.

## RELATED LINKS
