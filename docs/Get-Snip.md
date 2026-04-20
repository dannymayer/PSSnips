---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-Snip

## SYNOPSIS
Lists local snippets with optional filtering by name, description, tag, language, or content.

## SYNTAX

```
Get-Snip [[-Filter] <String>] [-Tag <String>] [-Language <String>] [-Content] [-SortBy <String>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads the snippet index (index.json) and outputs a formatted table of all
matching snippets.
Filtering is case-insensitive and matches against the snippet name, its
description, and its tags when -Filter is used.
When -Content is also specified the body of each snippet file is searched as well.
Use -Tag for an exact tag match or -Language to restrict by file extension.
Use -SortBy to control ordering: Name (default), Modified, RunCount, or LastRun.
Pinned snippets always float to the top of the list regardless of -SortBy.
Returns an array of PSCustomObject rows so results can be piped to other commands.

## EXAMPLES

### EXAMPLE 1
```
Get-Snip
```

Lists all snippets in the index, sorted by name.

### EXAMPLE 2
```
Get-Snip -Filter azure
```

Lists all snippets whose name, description, or tags contain 'azure'.

### EXAMPLE 3
```
Get-Snip -Filter azure -Content
```

Lists all snippets whose name, description, tags, OR file body contains 'azure'.

### EXAMPLE 4
```
Get-Snip -Tag devops -Language ps1
```

Lists PowerShell snippets tagged 'devops'.

### EXAMPLE 5
```
Get-Snip -SortBy RunCount
```

Lists all snippets ordered by run frequency (most-run first).

## PARAMETERS

### -Filter
Optional.
A wildcard substring matched against the snippet name, description, and tags.
Accepts partial strings (e.g., 'azure' matches 'azure-deploy').
When combined with -Content, the snippet file body is also searched.

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

### -Tag
Optional.
An exact tag value to filter by.
The snippet must have this tag in its tags array to be included in the results.

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

### -Language
Optional.
A file extension (without the dot) to restrict results to a single language
(e.g., 'py', 'ps1', 'js').

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

### -Content
Optional switch.
When specified together with -Filter, the body of each snippet file is also
searched for the filter string (case-insensitive).
Files that cannot be read are silently skipped.

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

### -SortBy
Optional.
Controls the sort order of the output.
Accepted values: Name (default, ascending), Modified (ascending),
RunCount (descending), LastRun (descending).
Pinned snippets always appear before non-pinned ones.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: Name
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

### System.Management.Automation.PSCustomObject[]
### Each object has Name, Lang, Gist, Tags, Modified, Desc, Runs, and Pinned properties.
### Returns nothing (displays an info message) when no snippets match.
## NOTES
The @($m.tags) wrapping inside the filter logic normalises tags to an array
even when the JSON deserializer returns a bare string for a single-element
array (a known PowerShell 5.1 ConvertFrom-Json quirk).
Run history fields (runCount, lastRun) are written to the index by Invoke-Snip.

## RELATED LINKS
