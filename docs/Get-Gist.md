---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-Gist

## SYNOPSIS
Displays the full content of a GitHub Gist including all its files.

## SYNTAX

```
Get-Gist [-GistId] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Fetches a specific Gist from the GitHub API by ID and prints each file's
content to the terminal with syntax-coloured headers.
If a file is marked
truncated in the API response, the raw_url is fetched separately to retrieve
the full content.
Returns the raw Gist API object for pipeline use.

## EXAMPLES

### EXAMPLE 1
```
Get-Gist abc123def456abc123def456abc1234567
```

Fetches and displays all files in the specified Gist.

### EXAMPLE 2
```
$gist = Get-Gist abc123def456abc123def456abc1234567
$gist.html_url
```

Retrieves the Gist object and accesses its HTML URL.

## PARAMETERS

### -GistId
Mandatory.
The GitHub Gist ID (32-character hex string) to retrieve.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### System.Object
### Returns the deserialized Gist object from the GitHub API containing id,
### description, html_url, files, owner, and related metadata.
## NOTES
Requires a GitHub PAT with the 'gist' scope.
Truncated file content (\>1 MB) is fetched via an additional web request
to the file's raw_url.

## RELATED LINKS
