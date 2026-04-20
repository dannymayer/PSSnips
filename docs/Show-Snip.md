---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Show-Snip

## SYNOPSIS
Displays the content of a named snippet in the terminal.

## SYNTAX

```
Show-Snip [-Name] <String> [-Raw] [-PassThru] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
Reads the snippet file from disk and writes its content to the terminal.
By default, a decorative header showing the snippet name, description, and
Gist URL (if linked) is printed before the content.
Use -Raw to suppress
the header and print only the raw file contents.
Use -PassThru to return the
content as a string for use in scripts or pipelines instead of printing it.

## EXAMPLES

### EXAMPLE 1
```
Show-Snip my-snippet
```

Displays the snippet content with a decorative header.

### EXAMPLE 2
```
Show-Snip my-snippet -PassThru | Set-Clipboard
```

Returns the snippet content as a string and copies it to the clipboard.

### EXAMPLE 3
```
Show-Snip my-snippet -Raw
```

Prints the raw file content without any header decoration.

## PARAMETERS

### -Name
Mandatory.
The name of the snippet to display (without file extension).

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

### -PassThru
Optional switch.
When specified, returns the snippet content as a string
instead of writing to the host.
The decorative header is not printed.

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

### -Raw
Optional switch.
When specified, suppresses the decorative header and prints
only the raw file content.

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

### System.String
### Only when -PassThru is specified. Returns the full file content as a string.
### Otherwise outputs nothing (writes directly to the host).
## NOTES
If the snippet name is not found in the file system, an error message is
displayed and the function returns without throwing.

## RELATED LINKS
