---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Export-GitLabSnip

## SYNOPSIS
Exports a local snippet to GitLab as a new or updated snippet.

## SYNTAX

```
Export-GitLabSnip [-Name] <String> [-Description <String>] [-Visibility <String>] [<CommonParameters>]
```

## DESCRIPTION
Creates (POST /api/v4/snippets) or updates (PUT /api/v4/snippets/<id>) a
GitLab snippet. After success, saves gitlabId and gitlabUrl to the index.
If the snippet already has a gitlabId, the existing GitLab snippet is updated.

## EXAMPLES

### EXAMPLE 1
```
Export-GitLabSnip my-snippet
```

Exports 'my-snippet' as a private GitLab snippet.

### EXAMPLE 2
```
Export-GitLabSnip my-snippet -Description 'Deploy script' -Visibility internal
```

Exports with a description and internal visibility.

## PARAMETERS

### -Name
Mandatory. The local snippet name to export.

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

### -Description
Optional. Description for the GitLab snippet.

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

### -Visibility
Optional. 'public', 'internal', or 'private'. Default: 'private'.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: private
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

## RELATED LINKS
