@{
    # PSScriptAnalyzer settings for PSSnips
    # https://github.com/PowerShell/PSScriptAnalyzer/blob/master/docs/Cmdlets/Invoke-ScriptAnalyzer.md#-settings

    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # PSSnips is a terminal UI module — Write-Host is intentional for coloured
        # interactive output. All non-UI output paths use Write-Error / Write-Verbose.
        'PSAvoidUsingWriteHost',

        # The module name itself is 'PSSnips' (plural by design). Functions prefixed
        # with the module name (Install-PSSnips, Sync-SharedSnips, etc.) inherit
        # the plural form from the brand name — this is intentional.
        'PSUseSingularNouns'
    )
}
