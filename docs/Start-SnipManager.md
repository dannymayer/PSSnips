---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Start-SnipManager

## SYNOPSIS
Launches the full-screen interactive terminal snippet manager (TUI).

## SYNTAX

```
Start-SnipManager [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Starts a full-screen text UI that displays a navigable list of snippets with
real-time search filtering.
The UI is drawn using \[Console\]::SetCursorPosition
for in-place redraws without flickering.
Navigation uses raw virtual key codes
read via $Host.UI.RawUI.ReadKey:
  VK 38 (Up arrow)    - move selection up
  VK 40 (Down arrow)  - move selection down
  VK 13 (Enter)       - open detail view
  VK 39 (Right arrow) - open detail view
  VK 27 (Esc)         - return to list view from detail
  VK 37 (Left arrow)  - return to list view from detail
Single-character commands (n, e, r, c, d, g, /) are handled in the default
branch of the key switch.
The cursor is hidden during TUI operation and
restored in a finally block to ensure visibility is not lost on error.

## EXAMPLES

### EXAMPLE 1
```
Start-SnipManager
```

Launches the interactive TUI snippet manager.

### EXAMPLE 2
```
snip
```

Equivalent shortcut: calling snip with no arguments starts the TUI.

## PARAMETERS

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

### None.
## OUTPUTS

### None. All interaction is through the console.
## NOTES
Requires an interactive host with RawUI support.
Will not work correctly
in non-interactive sessions (e.g., CI pipelines) or when stdout is
redirected.
The TUI shows up to 20 snippets per page; use \[/\] to filter
when the collection exceeds 20 items.

## RELATED LINKS
