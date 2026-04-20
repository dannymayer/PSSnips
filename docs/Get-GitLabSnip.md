---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-GitLabSnip

## SYNOPSIS
Fetches and displays a specific GitLab snippet by ID.

## SYNTAX

```
Get-GitLabSnip [-SnipId] <String> [<CommonParameters>]
```

## DESCRIPTION
Calls GET /api/v4/snippets/<id> and GET /api/v4/snippets/<id>/raw,
returning the snippet object with RawContent added. Displays the snippet
title, description, URL, and raw content in the terminal.

## EXAMPLES

### EXAMPLE 1
```
Get-GitLabSnip 12345
```

Fetches and displays GitLab snippet with ID 12345.

## PARAMETERS

### -SnipId
Mandatory. The GitLab snippet ID.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.

## INPUTS

### None.

## OUTPUTS

### System.Management.Automation.PSCustomObject

## NOTES
Requires GitLabToken config or $env:GITLAB_TOKEN.

## RELATED LINKS
