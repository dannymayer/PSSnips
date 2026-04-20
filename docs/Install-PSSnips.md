---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Install-PSSnips

## SYNOPSIS
Adds PSSnips to a PowerShell profile so it loads automatically.

## SYNTAX

```
Install-PSSnips [-Scope <String>] [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Locates the specified PowerShell profile file, creates it if it doesn't exist,
and appends an Import-Module line for PSSnips if not already present.
Supports -WhatIf to preview changes without modifying the profile.

## EXAMPLES

### EXAMPLE 1
```
Install-PSSnips
```

Adds PSSnips to the current user's current host profile.

### EXAMPLE 2
```
Install-PSSnips -Scope CurrentUserAllHosts
```

Adds PSSnips to the profile that loads for all hosts.

## PARAMETERS

### -Scope
The profile scope to modify. Default: CurrentUserCurrentHost.
Valid values: CurrentUserCurrentHost, CurrentUserAllHosts, AllUsersCurrentHost, AllUsersAllHosts.

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

### -Force
Optional switch. Adds the import line even if PSSnips is already in the profile.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.

## INPUTS

### None.

## OUTPUTS

### None.

## NOTES
After installation, restart PowerShell or dot-source the profile file.

## RELATED LINKS
