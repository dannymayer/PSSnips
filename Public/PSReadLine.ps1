# PSSnips — PSReadLine hotkey integration (Set-SnipReadLineKey).

function Set-SnipReadLineKey {
    <#
    .SYNOPSIS
        Binds a PSReadLine keyboard shortcut to open the PSSnips snippet picker.
    .DESCRIPTION
        Registers a PSReadLine key handler that invokes Invoke-FuzzySnip when the
        configured chord is pressed. The selected snippet content is inserted at the
        current cursor position in the readline buffer. Requires the PSReadLine module.
        Default chord: Ctrl+Alt+S.
    .PARAMETER Chord
        The key chord to bind. Default: 'Ctrl+Alt+s'.
    .PARAMETER Remove
        Removes the PSSnips key handler for the specified chord.
    .EXAMPLE
        Set-SnipReadLineKey
        Binds Ctrl+Alt+S to the PSSnips snippet picker.
    .EXAMPLE
        Set-SnipReadLineKey -Chord 'Ctrl+Alt+p'
        Binds Ctrl+Alt+P instead.
    .EXAMPLE
        Set-SnipReadLineKey -Remove
        Removes the Ctrl+Alt+S binding.
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Add Set-SnipReadLineKey to your PowerShell profile (or use Install-PSSnips
        -IncludeReadLineKey) to persist the binding across sessions.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [string]$Chord = 'Ctrl+Alt+s',
        [switch]$Remove
    )

    if (-not (Get-Module -ListAvailable -Name PSReadLine -ErrorAction SilentlyContinue)) {
        Write-Error "PSReadLine module not found. Install it with: Install-Module PSReadLine"
        return
    }

    if ($Remove) {
        if ($PSCmdlet.ShouldProcess($Chord, "Remove PSReadLine key handler")) {
            Remove-PSReadLineKeyHandler -Chord $Chord
            script:Out-OK "PSSnips hotkey removed: $Chord"
        }
        return
    }

    if ($PSCmdlet.ShouldProcess($Chord, "Bind PSReadLine key handler")) {
        Set-PSReadLineKeyHandler -Chord $Chord -ScriptBlock {
            $line = $null; $cursor = $null
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

            $content = $null
            try {
                if (Get-Command Invoke-FuzzySnip -ErrorAction SilentlyContinue) {
                    $content = Invoke-FuzzySnip -PassThru -ErrorAction SilentlyContinue
                }
            } catch { $_ | Out-Null }  # Invoke-FuzzySnip is optional; silently continue

            if ($content) {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($content)
            } else {
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert('Start-SnipManager')
            }
        }
        script:Out-OK "PSSnips hotkey bound: $Chord (press to invoke snippet picker)"
    }
}
