---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Copy-Snip

## SYNOPSIS
Copies a snippet's full content to the Windows clipboard.

## SYNTAX

```
Copy-Snip [-Name] <String> [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Retrieves the content of the named snippet via Show-Snip -PassThru and
passes it to Set-Clipboard.
The function writes a confirmation message if
successful and does nothing if the snippet is not found (Show-Snip handles
the error message in that case).

## EXAMPLES

### EXAMPLE 1
```
Copy-Snip my-snippet
```

Copies the content of 'my-snippet' to the clipboard.

### EXAMPLE 2
```
# Quickly grab a snippet to paste into a terminal
Copy-Snip azure-login
# then Ctrl+V in any application
```

## PARAMETERS

### -Name
Mandatory.
The name of the snippet whose content should be copied.

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

### None. Writes a confirmation message to the host on success.
## NOTES
Requires a Windows clipboard (Set-Clipboard).
In headless or SSH sessions
where the clipboard is unavailable, Set-Clipboard may throw; the error is
not suppressed.

## RELATED LINKS
