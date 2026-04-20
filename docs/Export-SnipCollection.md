---
external help file: PSSnips-help.xml
Module Name: PSSnips
online version:
schema: 2.0.0
---

# Export-SnipCollection

## SYNOPSIS
Exports the full local snippet collection to a portable ZIP archive.

## SYNTAX

```
Export-SnipCollection [[-Path] <String>] [-IncludeConfig] [-ProgressAction <ActionPreference>]
 [<CommonParameters>]
```

## DESCRIPTION
Gathers all snippet files from the configured SnippetsDir, the index.json
metadata file, and (optionally) config.json, then packages them into a ZIP
archive using Compress-Archive.
The archive layout mirrors the PSSnips data directory so that
Import-SnipCollection can restore it correctly:
    snippets\  — all snippet files
    index.json — snippet metadata index
    config.json (optional, only when -IncludeConfig is specified)
The default destination is ~/Desktop/PSSnips-backup-<yyyyMMdd-HHmmss>.zip.

## EXAMPLES

### EXAMPLE 1
```
Export-SnipCollection
```

Creates a timestamped backup ZIP on the Desktop.

### EXAMPLE 2
```
Export-SnipCollection -Path C:\Backups\my-snips.zip
```

Creates the backup at the specified path.

### EXAMPLE 3
```
Export-SnipCollection -IncludeConfig
```

Includes config.json in the archive (warns about potential token exposure).

## PARAMETERS

### -Path
Optional.
Destination path for the ZIP file.
When omitted, the archive is written to the current user's Desktop with a
timestamped name in the format PSSnips-backup-yyyyMMdd-HHmmss.zip.

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: False
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -IncludeConfig
Optional switch.
Also includes config.json in the backup.
A warning is displayed because config.json may contain a GitHub personal
access token in plain text.

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

### None. Writes a success message with the ZIP path and file count to the host.
## NOTES
Requires PowerShell 5.0+ for Compress-Archive (already satisfied by the
module's #Requires -Version 5.1 declaration).
The archive is built in a temporary staging directory that is automatically
removed after compression completes or on error.
Use Import-SnipCollection to restore from the backup archive.

## RELATED LINKS
