# PSSnips — Internal event dispatch helper.
function script:Invoke-SnipEvent {
    <#
    .SYNOPSIS
        Raises a named PSSnips lifecycle event, invoking all registered handlers.
    .NOTES
        Errors in individual handlers are silently swallowed via Write-Verbose to
        prevent a broken handler from disrupting normal module operations.
    #>
    param(
        [Parameter(Mandatory)][string]$EventName,
        [hashtable]$Data = @{}
    )
    if (-not $script:EventRegistry.ContainsKey($EventName)) { return }
    foreach ($handler in $script:EventRegistry[$EventName].Values) {
        try { & $handler $Data } catch { Write-Verbose "PSSnips event handler error [$EventName]: $_" }
    }
}

