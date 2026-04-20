---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Sync-SharedSnips

## SYNOPSIS
Imports snippets from shared storage into the local snippet collection.

## SYNTAX

```
Sync-SharedSnips [-Force] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Reads shared-index.json from SharedSnippetsDir and copies any snippet not
present locally (or all snippets with -Force) into the local collection.
Use Publish-Snip to add snippets to shared storage.

## EXAMPLES

### EXAMPLE 1
```
Sync-SharedSnips
```

Imports only new snippets (not already present locally) from shared storage.

### EXAMPLE 2
```
Sync-SharedSnips -Force
```

Imports all shared snippets, overwriting local ones.

## PARAMETERS

### -Force
Optional switch. Imports all shared snippets, overwriting local ones.

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
