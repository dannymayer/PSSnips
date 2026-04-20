---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Sync-Gist

## SYNOPSIS
Synchronises a local snippet with its linked GitHub Gist (pull or push).

## SYNTAX

```
Sync-Gist [-Name] <String> [-Push] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Bi-directional sync between a local snippet and the GitHub Gist it was
linked to via Export-Gist or Import-Gist.
By default (pull mode) the local
snippet file is overwritten with the latest content from GitHub.
With -Push,
the local file's current content is uploaded to GitHub, updating the Gist.
The snippet must already have a linked gistId; run Export-Gist first to
establish the link.

## EXAMPLES

### EXAMPLE 1
```
Sync-Gist my-snippet
```

Pulls the latest Gist content from GitHub into the local snippet file.

### EXAMPLE 2
```
Sync-Gist my-snippet -Push
```

Uploads the current local snippet content to the linked GitHub Gist.

## PARAMETERS

### -Name
Mandatory.
The name of the local snippet to synchronise.

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

### -Push
Optional switch.
Pushes the local snippet content to GitHub (update Gist).
Without this switch, the default is to pull (download from GitHub).

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

### None. Writes a status message to the host.
## NOTES
Pull mode calls Import-Gist -Force which overwrites the local file.
Push mode calls Export-Gist which PATCHes the existing Gist.
The snippet must have a non-null gistId in the index.
If not, an error
is displayed directing the user to run Export-Gist first.

## RELATED LINKS
