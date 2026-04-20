---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Edit-Snip

## SYNOPSIS
Opens a snippet file in the configured editor and updates its modified timestamp.

## SYNTAX

```
Edit-Snip [-Name] <String> [-Editor <String>] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Resolves the snippet file path, launches the configured editor (or an override),
and waits for the editor process to exit.
After the editor closes, the snippet's
'modified' timestamp in index.json is updated to the current UTC time.
The editor resolution order is: -Editor override → configured Editor →
EditorFallbacks list (nvim, code, notepad) → notepad as the final fallback.

## EXAMPLES

### EXAMPLE 1
```
Edit-Snip my-snippet
```

Opens 'my-snippet' in the default configured editor.

### EXAMPLE 2
```
Edit-Snip my-snippet -Editor code
```

Opens 'my-snippet' in Visual Studio Code regardless of the configured editor.

## PARAMETERS

### -Editor
Optional.
Overrides the configured editor for this invocation only.
Must be a command resolvable on PATH (e.g., 'code', 'nvim', 'notepad').

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
The name of the snippet to edit.

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

### None. The editor runs synchronously; control returns after the editor exits.
## NOTES
The function calls script:GetEditor which walks the Editor and EditorFallbacks
configuration keys.
The @($cfg.Editor) wrapping ensures the Editor value is
always iterated as an array even when stored as a bare string in the config.

Before launching the editor, the current snippet content is automatically saved
as a timestamped version snapshot in ~/.pssnips/history/<name>/. This allows
rolling back to any pre-edit state using Restore-Snip. The number of retained
snapshots is controlled by the MaxHistory configuration setting (default: 10).
Use Get-SnipHistory to list available snapshots.

## RELATED LINKS
