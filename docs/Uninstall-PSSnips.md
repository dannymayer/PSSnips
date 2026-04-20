---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Uninstall-PSSnips

## SYNOPSIS
Removes PSSnips from a PowerShell profile.

## SYNTAX

```
Uninstall-PSSnips [-Scope <String>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Reads the specified profile file and removes any lines containing 'PSSnips',
then writes the cleaned content back. Supports -WhatIf to preview changes.

## EXAMPLES

### EXAMPLE 1
```
Uninstall-PSSnips
```

Removes PSSnips from the current user's current host profile.

## PARAMETERS

### -Scope
The profile scope to modify. Default: CurrentUserCurrentHost.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: CurrentUserCurrentHost
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.

## INPUTS

### None.

## OUTPUTS

### None.

## NOTES
Supports -WhatIf.

## RELATED LINKS
