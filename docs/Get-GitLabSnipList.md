---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-GitLabSnipList

## SYNOPSIS
Lists GitLab snippets for the authenticated user.

## SYNTAX

```
Get-GitLabSnipList [-Filter <String>] [-Count <UInt32>] [<CommonParameters>]
```

## DESCRIPTION
Calls the GitLab Snippets API (GET /api/v4/snippets) and displays a formatted
table of snippets showing ID, Title, Visibility, and FileName.
Requires GitLabToken config or $env:GITLAB_TOKEN.

## EXAMPLES

### EXAMPLE 1
```
Get-GitLabSnipList
```

Lists all GitLab snippets for the authenticated user.

### EXAMPLE 2
```
Get-GitLabSnipList -Filter 'deploy' -Count 50
```

Lists GitLab snippets whose title or filename contains 'deploy', up to 50 results.

## PARAMETERS

### -Filter
Optional substring to match against title and file_name.

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

### -Count
Optional. Maximum number of snippets to retrieve. Default: 30.

```yaml
Type: System.UInt32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable.

## INPUTS

### None.

## OUTPUTS

### System.Management.Automation.PSCustomObject[]

## NOTES
Requires GitLabToken config or $env:GITLAB_TOKEN.
Configure via: snip config -GitLabToken <token>

## RELATED LINKS
