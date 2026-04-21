# PSSnips — Comment-Based Help parser.
function script:ParseCBH {
    <#
    .SYNOPSIS
        Parses PowerShell comment-based help from script content.
    .DESCRIPTION
        Extracts .SYNOPSIS, .DESCRIPTION, and Tags from the .NOTES section of the
        first block-comment CBH section found in the provided content string.
        Returns a hashtable with keys: Synopsis (string), Description (string),
        Tags (string[]).
    .NOTES
        Only block-comment CBH (angle-bracket hash ... hash angle-bracket) is supported.
        Line-comment CBH is not parsed. Tags are extracted from a "Tags: value1, value2"
        line inside the .NOTES keyword section.
    #>
    param([Parameter(Mandatory)][string]$Content)
    $result = @{ Synopsis = [string]$null; Description = [string]$null; Tags = @() }
    if ($Content -notmatch '(?s)<#\s*(.*?)\s*#>') { return $result }
    $block = $Matches[1]
    # Single-line .SYNOPSIS — first non-blank line after the keyword
    if ($block -match '(?m)\.SYNOPSIS[ \t]*\r?\n([ \t]*\S[^\r\n]*)') {
        $result.Synopsis = $Matches[1].Trim()
    }
    # Multi-line .DESCRIPTION — everything up to the next .KEYWORD or end of block
    if ($block -match '(?s)\.DESCRIPTION[ \t]*\r?\n(.*?)(?=\r?\n[ \t]*\.\w|\z)') {
        $lines = ($Matches[1] -split '\r?\n') |
            ForEach-Object { $_.Trim() } |
            Where-Object   { $_ }
        if ($lines) { $result.Description = ($lines -join ' ').Trim() }
    }
    # Tags: line inside .NOTES (comma- or space-separated)
    if ($block -match '(?s)\.NOTES.*?Tags?:[ \t]*([^\r\n]+)') {
        $result.Tags = @(
            ($Matches[1].Trim() -split '[,\s]+') |
                ForEach-Object { $_.Trim() } |
                Where-Object   { $_ }
        )
    }
    return $result
}

