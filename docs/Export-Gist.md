---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Export-Gist

## SYNOPSIS
Exports a local snippet to GitHub as a new or updated Gist.

## SYNTAX

```
Export-Gist [-Name] <String> [-Description <String>] [-Public] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Reads the snippet file and its metadata, then creates a new GitHub Gist via
POST or updates the existing linked Gist via PATCH.
The decision is based on
whether the snippet's 'gistId' field in the index is set.
After a successful
API call, the Gist ID and URL are written back to index.json so that future
calls update the same Gist.
New Gists are secret by default; use -Public to
create a publicly visible Gist.

## EXAMPLES

### EXAMPLE 1
```
Export-Gist my-snippet
```

Creates a secret Gist from 'my-snippet' or updates the linked one.

### EXAMPLE 2
```
Export-Gist my-snippet -Description 'Handy deploy script' -Public
```

Creates or updates a public Gist with a specific description.

## PARAMETERS

### -Description
Optional.
A description for the Gist.
Falls back to the snippet's description,
then the snippet name if not provided.

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

### -Name
Mandatory.
The name of the local snippet to export.

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

### -Public
Optional switch.
Creates a public Gist.
Default is a secret Gist.

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
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### None. Writes the resulting Gist URL to the host on success.
## NOTES
Requires a GitHub PAT with the 'gist' scope.
If the snippet has a gistId in the index, the Gist is updated (PATCH).
If not, a new Gist is created (POST) and the ID is saved to the index.

## RELATED LINKS
