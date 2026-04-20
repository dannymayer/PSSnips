---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Invoke-Snip

## SYNOPSIS
Executes a snippet or runs multiple snippets in sequence (pipeline/chain mode).

## SYNTAX

### Single (default)
```
Invoke-Snip [-Name] <String> [[-ArgumentList] <String[]>] [-Variables <Hashtable>]
 [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

### Chain
```
Invoke-Snip -Pipeline <String[]> [-ContinueOnError] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Single mode (-Name): resolves the snippet file, substitutes any {{PLACEHOLDER}}
template variables in the content, then invokes the appropriate language runner.
Runner selection: .ps1/.psm1 (dot-source), .py (python/python3), .js (node),
.bat/.cmd (cmd /c), .sh (bash/wsl), .rb (ruby), .go (go run), other (Start-Process).

Chain mode (-Pipeline): runs multiple snippets sequentially. Prints a header,
executes each snippet by name in order, and prints a summary. By default stops
on the first error unless -ContinueOnError is specified.

After each single execution the snippet''s runCount is incremented and lastRun
is set in index.json. A failure to update run history never prevents output.

## EXAMPLES

### EXAMPLE 1
```
Invoke-Snip deploy-script
```

Runs the ''deploy-script'' snippet using the appropriate runner.

### EXAMPLE 2
```
Invoke-Snip my-py-script -ArgumentList ''--verbose'', ''--dry-run''
```

Runs a Python snippet and passes ''--verbose --dry-run'' to the interpreter.

### EXAMPLE 3
```
Invoke-Snip deploy -Variables @{ ENV = ''prod''; REGION = ''eastus'' }
```

Runs ''deploy'' filling {{ENV}} and {{REGION}} without interactive prompts.

### EXAMPLE 4
```
Invoke-Snip -Pipeline ''setup'',''build'',''deploy''
```

Runs three snippets in sequence. Stops on the first failure.

### EXAMPLE 5
```
Invoke-Snip -Pipeline ''setup'',''build'',''deploy'' -ContinueOnError
```

Runs all three snippets, reporting errors but not stopping.

## PARAMETERS

### -ArgumentList
Optional (Single set). Additional arguments passed to the language runner after
the snippet file path. Accepts remaining arguments positionally.

```yaml
Type: System.String[]
Parameter Sets: Single
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ContinueOnError
Optional (Chain set). When set, pipeline execution continues even if a snippet
in the chain fails. Without this switch, the pipeline stops at the first error.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: Chain
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -Name
Mandatory (Single set). The name of the snippet to execute.

```yaml
Type: System.String
Parameter Sets: Single
Aliases:

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Pipeline
Mandatory (Chain set). An array of snippet names to run in sequence.
You may also pass a single comma-separated string which is split automatically.

```yaml
Type: System.String[]
Parameter Sets: Chain
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Variables
Optional (Single set). A hashtable of placeholder values used to fill
{{VARIABLE_NAME}} placeholders in the snippet body without prompting.
Keys must match placeholder names exactly (case-insensitive match supported).
Any placeholder NOT found in this hashtable will be prompted interactively.

```yaml
Type: System.Collections.Hashtable
Parameter Sets: Single
Aliases:

Required: False
Position: Named
Default value: @{}
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

### Variable. Output depends on the language runner.
## NOTES
Template variables use the syntax {{VARIABLE_NAME}} (uppercase letters, digits,
and underscores). Matching is case-insensitive for the -Variables hashtable
lookup. If any substitutions are made, the snippet runs from a temporary file
that is deleted in a finally block.
For .sh snippets on Windows, bash is sought first; then wsl bash.
Run history (runCount, lastRun) is updated in index.json after execution.
Use Get-Snip -SortBy RunCount or -SortBy LastRun to surface frequently-used snippets.

## RELATED LINKS
