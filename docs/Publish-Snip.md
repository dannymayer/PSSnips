---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Publish-Snip

## SYNOPSIS
Copies a local snippet to the configured shared storage directory.

## SYNTAX

```
Publish-Snip [-Name] <String> [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Copies the snippet file to SharedSnippetsDir and updates shared-index.json
in the shared directory with the snippet's metadata. Other users or machines
with access to the same SharedSnippetsDir can use Sync-SharedSnips to import.

## EXAMPLES

### EXAMPLE 1
```
Publish-Snip my-snippet
```

Publishes 'my-snippet' to the configured shared storage directory.

### EXAMPLE 2
```
Publish-Snip my-snippet -Force
```

Overwrites the snippet in shared storage if it already exists.

## PARAMETERS

### -Name
Mandatory. The local snippet name to publish.

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

### -Force
Optional switch. Overwrites the snippet in shared storage if it already exists.

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
SharedSnippetsDir must be set via Set-SnipConfig -SharedSnippetsDir <path>.

## RELATED LINKS
