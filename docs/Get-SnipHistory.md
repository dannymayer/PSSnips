---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Get-SnipHistory

## SYNOPSIS
Lists saved version history for a snippet.

## SYNTAX

```
Get-SnipHistory [-Name] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Returns all timestamped version snapshots for the named snippet stored in the
~/.pssnips/history/<name> directory. Versions are listed newest first, numbered
from 1 (most recent). Version snapshots are created automatically by Edit-Snip
(before the editor opens), Add-Snip -Force, and New-Snip -Force -Content. Use
Restore-Snip to roll back to any previous version.

## EXAMPLES

### EXAMPLE 1
```
Get-SnipHistory my-snippet
```

Lists all saved versions of 'my-snippet', newest first.

### EXAMPLE 2
```
$history = Get-SnipHistory my-snippet
$history[0].Path  # path to the most recent version file
```

Captures the history objects and accesses the path of the most recent version.

## PARAMETERS

### -Name
Mandatory. The name of the snippet whose history to display.

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
Each object has Version (int), Timestamp (datetime), Size (int), and Path (string)
properties. Returns an empty array when no history exists.

## NOTES
History snapshots are pruned automatically to MaxHistory (default 10) entries per
snippet. Older snapshots are removed first when the limit is exceeded. The history
directory is at ~/.pssnips/history/<snippetName>/. Configure MaxHistory with
Set-SnipConfig -MaxHistory <n>.

## RELATED LINKS
