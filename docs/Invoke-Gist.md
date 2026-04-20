---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Invoke-Gist

## SYNOPSIS
Downloads and executes a GitHub Gist file without saving it locally.

## SYNTAX

```
Invoke-Gist [-GistId] <String> [-FileName <String>] [-ArgumentList <String[]>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
Fetches a Gist from GitHub, writes the selected file to a temporary path in
$env:TEMP, executes it with the appropriate language runner, and then deletes
the temporary file in a finally block.
The runner selection follows the same
logic as Invoke-Snip (ps1, py, js, bat/cmd, sh, rb, go).
Supports -WhatIf
via ShouldProcess - with -WhatIf the file is not written or executed.
When the Gist has multiple files, the first file matching a known runnable
extension is selected automatically; use -FileName to specify explicitly.

## EXAMPLES

### EXAMPLE 1
```
Invoke-Gist abc123def456abc123def456abc1234567
```

Fetches and executes the runnable file in the specified Gist.

### EXAMPLE 2
```
Invoke-Gist abc123def456abc123def456abc1234567 -FileName script.ps1
```

Runs the named file from the Gist.

### EXAMPLE 3
```
Invoke-Gist abc123def456abc123def456abc1234567 -WhatIf
```

Shows what would be executed without actually running it.

## PARAMETERS

### -ArgumentList
Optional.
Arguments forwarded to the language runner after the file path.

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

### -FileName
Optional.
The specific file within the Gist to run.
When omitted, the first
file with a known runnable extension is selected.

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

### -GistId
Mandatory.
The GitHub Gist ID to fetch and run.

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
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

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

### Variable. Output depends on the language runner.
## NOTES
The temporary file is always deleted after execution (or on error) via a
try/finally block.
The temp file is placed in $env:TEMP with a random name.
Requires a GitHub PAT with the 'gist' scope.

## RELATED LINKS
