---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Restore-Snip

## SYNOPSIS
Restores a snippet to a previous version from its version history.

## SYNTAX

```
Restore-Snip [-Name] <String> [[-Version] <Int32>] [-WhatIf] [-Confirm]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Looks up the version history for the named snippet, saves the current content as
a new history entry (to allow re-restore if needed), then copies the selected
historical version back to the snippets directory and updates the snippet's
'modified' timestamp in the index. Version 1 is the most recent saved version,
version 2 is the second most recent, and so on. Use Get-SnipHistory to see the
available version numbers.

## EXAMPLES

### EXAMPLE 1
```
Restore-Snip my-snippet
```

Restores 'my-snippet' to its most recent saved version (Version 1).

### EXAMPLE 2
```
Restore-Snip my-snippet -Version 3
```

Restores 'my-snippet' to the third most recent saved version.

### EXAMPLE 3
```
Get-SnipHistory my-snippet
Restore-Snip my-snippet -Version 2
```

Lists versions, then restores the second most recent one.

## PARAMETERS

### -Name
Mandatory. The name of the snippet to restore.

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

### -Version
Optional. The version number to restore. 1 is the most recent saved version
(default). Use Get-SnipHistory to see available version numbers.

```yaml
Type: System.Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: 1
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs without actually restoring.

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

### None. Writes a success or error message to the host.
## NOTES
The current snippet content is saved as a new history entry before overwriting,
so you can re-restore the version you are replacing. Supports -WhatIf via
SupportsShouldProcess.

## RELATED LINKS
