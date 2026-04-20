---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Set-SnipTag

## SYNOPSIS
Manages the tags on a local snippet: replace, add, or remove individual tags.
Also supports pinning (favouriting) snippets.

## SYNTAX

```
Set-SnipTag [-Name] <String> [-Tags <String[]>] [-Add <String[]>] [-Remove <String[]>]
 [-Pin] [-Unpin] [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Loads the snippet's current tags from index.json and applies one of three
mutations depending on the parameters provided:
  -Tags    Replaces all existing tags with the supplied array.
  -Add     Appends each supplied tag that is not already present (no duplicates).
  -Remove  Removes each supplied tag from the current tag list.
The updated tag list is saved back to index.json and the snippet's 'modified'
timestamp is refreshed.
Tags are stored as a string array in the index.

Pin/Unpin operations are independent of tag operations and can be combined:
  -Pin     Marks the snippet as a favourite (pinned = $true).
  -Unpin   Removes the favourite mark (pinned = $false).

## EXAMPLES

### EXAMPLE 1
```
Set-SnipTag my-snippet -Tags @('devops', 'azure')
```

Replaces all tags on 'my-snippet' with 'devops' and 'azure'.

### EXAMPLE 2
```
Set-SnipTag my-snippet -Add 'cloud'
```

Appends the tag 'cloud' to the existing tags without removing any.

### EXAMPLE 3
```
Set-SnipTag my-snippet -Remove 'old-tag'
```

Removes the tag 'old-tag' while keeping all other tags intact.

### EXAMPLE 4
```
Set-SnipTag my-snippet -Pin
```

Marks 'my-snippet' as a favourite so it sorts to the top of all listings.

### EXAMPLE 5
```
Set-SnipTag my-snippet -Pin -Add 'cloud'
```

Pins the snippet AND appends the tag 'cloud' in a single call.

## PARAMETERS

### -Add
Optional.
Tags to append to the existing set.
Duplicates are silently ignored.

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -Name
Mandatory.
The name of the snippet to update.

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

### -Pin
Optional switch.
Marks the snippet as pinned (favourite).
Pinned snippets appear at the top of all Get-Snip listings with a ★ indicator.

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

### -Remove
Optional.
Tags to remove from the existing set.
Tags not present are ignored.

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -Tags
Optional.
Replaces the snippet's entire tag set with these values.

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: @()
Accept pipeline input: False
Accept wildcard characters: False
```

### -Unpin
Optional switch.
Removes the pinned (favourite) mark from the snippet.

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

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs. The cmdlet is not run.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases: wi

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

### None. Writes a confirmation message listing the updated tags.
## NOTES
Tags are normalised through \[System.Collections.Generic.List\[string\]\] to
guarantee correct array serialisation in JSON (PowerShell 7.0+ ConvertTo-Json
preserves single-element arrays natively, but the List normalisation is
retained for defensive correctness).

## RELATED LINKS
