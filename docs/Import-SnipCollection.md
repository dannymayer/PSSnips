---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Import-SnipCollection

## SYNOPSIS
Restores a snippet collection from a PSSnips backup ZIP archive.

## SYNTAX

```
Import-SnipCollection [-Path] <String> [-Merge] [-Force] [-WhatIf] [-Confirm]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Extracts a ZIP archive created by Export-SnipCollection and copies the
snippet files and index into the configured SnippetsDir.
Three import modes are supported:

  Default (no switches)
    If the snippets directory already contains files, warns and aborts to
    prevent accidental overwrites.
    Use -Merge or -Force to proceed.

  -Merge
    Adds backup snippets that do not already exist locally.
    Existing local snippets are preserved unless -Force is also specified.

  -Force (without -Merge)
    Replaces all local snippets with the backup contents without prompting.

  -Merge -Force
    Imports all backup snippets, overwriting any local snippets on conflict.

## EXAMPLES

### EXAMPLE 1
```
Import-SnipCollection -Path C:\Backups\my-snips.zip
```

Restores snippets from the backup. Aborts if local snippets already exist.

### EXAMPLE 2
```
Import-SnipCollection -Path C:\Backups\my-snips.zip -Merge
```

Adds new snippets from the backup; existing local snippets are unaffected.

### EXAMPLE 3
```
Import-SnipCollection -Path C:\Backups\my-snips.zip -Force
```

Replaces all local snippets with the contents of the backup.

### EXAMPLE 4
```
Import-SnipCollection -Path C:\Backups\my-snips.zip -Merge -Force
```

Imports all backup snippets, overwriting local snippets on any conflict.

## PARAMETERS

### -Path
Mandatory.
Path to the PSSnips backup ZIP file created by Export-SnipCollection.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Merge
Optional switch.
Merges backup snippets into the existing collection.
New snippets from the backup are added; existing local snippets are kept
unless -Force is also specified.

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

### -Force
Optional switch.
When used alone, replaces all local snippets with backup contents.
When used with -Merge, overwrites existing local snippets on conflict.

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

### -WhatIf
Shows what would happen if the cmdlet runs.

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

### None. Writes a summary of imported snippets to the host.
## NOTES
The archive is extracted to a temporary directory which is automatically
removed after the import completes or on error.
Supports -WhatIf via SupportsShouldProcess on Force (non-Merge) mode.
Use Export-SnipCollection to create a backup archive before importing.

## RELATED LINKS
