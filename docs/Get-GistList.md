---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-GistList

## SYNOPSIS
Lists GitHub Gists for the authenticated user or a specified GitHub username.

## SYNTAX

```
Get-GistList [[-Filter] <String>] [[-Count] <UInt32>] [[-Username] <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Calls the GitHub Gists API to retrieve a list of Gists and displays them in a
formatted table showing the Gist ID, description, and file names.
The number
of results is controlled by -Count (default 30, max 100 per API call).
Use
-Filter to restrict results to Gists whose description or file names contain
the given substring.
Returns the raw API response objects for pipeline use.

## EXAMPLES

### EXAMPLE 1
```
Get-GistList
```

Lists the 30 most recent Gists for the configured user.

### EXAMPLE 2
```
Get-GistList -Filter 'deploy' -Count 50
```

Lists up to 50 Gists whose description or file name contains 'deploy'.

### EXAMPLE 3
```
Get-GistList -Username octocat
```

Lists public Gists for the GitHub user 'octocat'.

## PARAMETERS

### -Count
Optional.
Maximum number of Gists to retrieve per API request.
Default: 30.

```yaml
Type: System.UInt32
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: 30
Accept pipeline input: False
Accept wildcard characters: False
```

### -Filter
Optional.
A substring to match against Gist descriptions and file names.
Case-insensitive.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
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

### -Username
Optional.
Retrieve Gists for a different GitHub user.
When omitted, defaults
to the configured GitHubUsername, or the authenticated user's Gists.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### System.Object[]
### Returns the deserialized Gist API response objects. Each object contains id,
### description, html_url, files, and other GitHub API fields.
## NOTES
Requires a GitHub PAT with the 'gist' scope.
Set via: Set-SnipConfig -GitHubToken 'ghp_...'  or  $env:GITHUB_TOKEN

## RELATED LINKS
