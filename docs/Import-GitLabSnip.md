---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Import-GitLabSnip

## SYNOPSIS
Downloads a GitLab snippet and saves it as a local snippet.

## SYNTAX

```
Import-GitLabSnip [-SnipId] <String> [-Name <String>] [-Force] [<CommonParameters>]
```

## DESCRIPTION
Fetches the raw content from /api/v4/snippets/<id>/raw and metadata from
/api/v4/snippets/<id>, then saves to local snippets dir and registers in
the index with gitlabId and gitlabUrl fields for future sync.

## EXAMPLES

### EXAMPLE 1
```
Import-GitLabSnip 12345
```

Imports GitLab snippet 12345 using the original filename.

### EXAMPLE 2
```
Import-GitLabSnip 12345 -Name my-local-name -Force
```

Imports snippet 12345 with the local name 'my-local-name', overwriting if exists.

## PARAMETERS

### -SnipId
Mandatory. The GitLab snippet ID to import.

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

### -Name
Optional. Override the local snippet name.

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
Optional switch. Overwrites existing snippet with the same name.

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
Requires GitLabToken config or $env:GITLAB_TOKEN.
The gitlabId and gitlabUrl are stored in the index for future sync.

## RELATED LINKS
