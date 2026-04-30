# PSSnips — Snippet diff / preview before import.

function Compare-SnipCollection {
    <#
    .SYNOPSIS
        Previews what would change if you ran Import-SnipCollection against a ZIP archive.

    .DESCRIPTION
        Extracts the specified PSSnips ZIP archive to a temporary directory and compares its
        index.json against the current local index.json.  Each snippet is classified as one of:

          Added      — present in the archive but not in the local collection.
          Modified   — present in both but with a different contentHash or modified timestamp.
          Unchanged  — present in both with an identical contentHash.
          LocalOnly  — present locally but not in the archive (import would not affect these).

        Without -PassThru the function prints a formatted summary table and per-category counts
        to the host.  With -PassThru it returns an array of PSCustomObject instead, which is
        useful for scripting or piping to further filtering.

        The temporary extraction directory is always removed on exit, even if an error occurs.

    .PARAMETER Path
        Full or relative path to the PSSnips ZIP archive produced by Export-SnipCollection.

    .PARAMETER PassThru
        When specified, returns an array of PSCustomObject instead of printing to host.
        Each object has the properties: Name, Status, LocalModified, ArchiveModified,
        Language, Tags.

    .EXAMPLE
        Compare-SnipCollection -Path .\backup.zip

        Prints a formatted preview table and summary counts to the host.

    .EXAMPLE
        $diff = Compare-SnipCollection -Path .\backup.zip -PassThru
        $diff | Where-Object Status -eq 'Modified'

        Returns result objects and filters to only the modified snippets.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        PSCustomObject[]
        Only emitted when -PassThru is specified.  Each object contains:
        Name, Status, LocalModified, ArchiveModified, Language, Tags.

    .NOTES
        Status values: Added, Modified, Unchanged, LocalOnly.
        LocalOnly snippets are informational — Import-SnipCollection does not remove them.
        Requires PowerShell 7.0 or later (module-wide requirement).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, HelpMessage = 'Path to the PSSnips ZIP archive to compare')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [switch]$PassThru
    )

    script:InitEnv

    if (-not (Test-Path $Path)) {
        Write-Error "Archive not found: $Path"
        return
    }

    $tempDir = Join-Path $env:TEMP "pssnips_compare_$(New-Guid)"

    try {
        Expand-Archive -Path $Path -DestinationPath $tempDir -Force

        $archiveIdxPath = Join-Path $tempDir 'index.json'
        if (-not (Test-Path $archiveIdxPath)) {
            Write-Error 'Archive does not contain index.json'
            return
        }

        $archiveRaw   = Get-Content $archiveIdxPath -Raw | ConvertFrom-Json -AsHashtable
        $archiveSnips = if ($archiveRaw.ContainsKey('snippets')) { $archiveRaw['snippets'] } else { @{} }

        $localIdx   = script:LoadIdx
        $localSnips = $localIdx.snippets

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($name in $archiveSnips.Keys) {
            $arch     = $archiveSnips[$name]
            $archHash = if ($arch -is [hashtable] -and $arch.ContainsKey('contentHash')) { $arch['contentHash'] } else { '' }
            $archMod  = if ($arch -is [hashtable] -and $arch.ContainsKey('modified'))    { try { [datetime]$arch['modified'] } catch { $null } } else { $null }
            $archLang = if ($arch -is [hashtable] -and $arch.ContainsKey('language'))    { $arch['language'] } else { '' }
            $archTags = if ($arch -is [hashtable] -and $arch.ContainsKey('tags'))        { @($arch['tags']) -join ',' } else { '' }

            if (-not $localSnips.ContainsKey($name)) {
                $status   = 'Added'
                $localMod = $null
            } else {
                $local     = $localSnips[$name]
                $localHash = $local.ContentHash
                $localMod  = $local.Modified
                $status    = if ($archHash -and $localHash -and $archHash -ne $localHash) { 'Modified' } else { 'Unchanged' }
            }

            $results.Add([PSCustomObject]@{
                Name            = $name
                Status          = $status
                LocalModified   = $localMod
                ArchiveModified = $archMod
                Language        = $archLang
                Tags            = $archTags
            })
        }

        foreach ($name in $localSnips.Keys) {
            if (-not $archiveSnips.ContainsKey($name)) {
                $local = $localSnips[$name]
                $results.Add([PSCustomObject]@{
                    Name            = $name
                    Status          = 'LocalOnly'
                    LocalModified   = $local.Modified
                    ArchiveModified = $null
                    Language        = $local.Language
                    Tags            = ($local.Tags -join ',')
                })
            }
        }

        if ($PassThru) {
            return $results.ToArray()
        }

        $added     = @($results | Where-Object Status -eq 'Added').Count
        $modified  = @($results | Where-Object Status -eq 'Modified').Count
        $unchanged = @($results | Where-Object Status -eq 'Unchanged').Count
        $localOnly = @($results | Where-Object Status -eq 'LocalOnly').Count

        script:Out-Info "Collection comparison: $Path"
        Write-Host ''
        $results | Sort-Object Status, Name | Format-Table Name, Status, Language, ArchiveModified -AutoSize
        Write-Host ''
        script:Out-OK "Summary — Added: $added  Modified: $modified  Unchanged: $unchanged  LocalOnly: $localOnly"
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
