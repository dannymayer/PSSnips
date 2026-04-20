---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Test-Snip

## SYNOPSIS
Runs PSScriptAnalyzer lint checks on a PowerShell snippet.

## SYNTAX

```
Test-Snip [-Name] <String> [-Severity <String>] [-PassThru] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Resolves the snippet file path, verifies PSScriptAnalyzer is available, and runs
Invoke-ScriptAnalyzer against the file. Results are displayed in a colour-coded
table: errors in Red, warnings in Yellow, information in DarkCyan. When no issues
are found a green success message is printed. Only applies to .ps1 and .psm1 files;
an informational message is shown for other extensions.

## EXAMPLES

### EXAMPLE 1
```
Test-Snip my-snippet
```

Runs all PSScriptAnalyzer rules against 'my-snippet.ps1'.

### EXAMPLE 2
```
Test-Snip my-snippet -Severity Error
```

Reports only Error-severity findings for 'my-snippet'.

### EXAMPLE 3
```
$results = Test-Snip my-snippet -PassThru
$results | Where-Object Severity -eq 'Error'
```

Returns raw result objects for further processing.

## PARAMETERS

### -Name
Mandatory. The name of the snippet to analyse.

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

### -Severity
Optional. Restrict results to a specific severity level: Error, Warning,
Information, or ParseError. When omitted all severities are returned.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:
Accepted values: Error, Warning, Information, ParseError

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PassThru
Optional switch. Returns the raw Invoke-ScriptAnalyzer result objects instead
of printing the formatted table. Useful for scripted inspection.

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

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None. This function does not accept pipeline input.
## OUTPUTS

### System.Management.Automation.PSCustomObject[]
Only when -PassThru is specified. Otherwise writes to the host.

## NOTES
Requires the PSScriptAnalyzer module. Install with:
  Install-Module PSScriptAnalyzer -Scope CurrentUser
Test-Snip only analyses .ps1 and .psm1 files. Other extensions receive an
informational message and the function returns without error.

## RELATED LINKS
