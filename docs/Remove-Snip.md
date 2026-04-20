---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Remove-Snip

## SYNOPSIS
Deletes a local snippet file and removes its index entry.

## SYNTAX

```
Remove-Snip [-Name] <String> [-Force] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm]
 [<CommonParameters>]
```

## DESCRIPTION
Looks up the snippet by name in the index, optionally prompts for
confirmation (based on the ConfirmDelete config setting or the -Force
switch), deletes the snippet file from disk, and removes the metadata
entry from index.json.
If the snippet name is not found the function
displays an error and returns without throwing.

## EXAMPLES

### EXAMPLE 1
```
Remove-Snip old-script
```

Deletes 'old-script', prompting for confirmation if ConfirmDelete is $true.

### EXAMPLE 2
```
Remove-Snip old-script -Force
```

Deletes 'old-script' immediately without any confirmation prompt.

## PARAMETERS

### -Force
Optional switch.
Bypasses the interactive confirmation prompt regardless
of the ConfirmDelete configuration setting.

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

### -Name
Mandatory.
The name of the snippet to delete.

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
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

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

### None. Writes a success or error message to the host.
## NOTES
The physical file and the index entry are both removed.
This action is
not reversible.
Linked GitHub Gists are not affected.

## RELATED LINKS
