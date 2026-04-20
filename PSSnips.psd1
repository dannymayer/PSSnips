@{
    RootModule        = 'PSSnips.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f3a7c2b1-84e9-4d56-a021-6c3e9f182b47'
    Author            = 'PSSnips'
    CompanyName       = 'Community'
    Copyright         = '(c) 2025 PSSnips contributors. MIT License.'
    Description       = 'Terminal snippet manager with GitHub Gist integration for Windows PowerShell environments.'
    PowerShellVersion = '5.1'
    HelpInfoUri       = ''

    FunctionsToExport = @(
        'Initialize-PSSnips',
        'Get-SnipConfig', 'Set-SnipConfig',
        'Get-Snip', 'Show-Snip', 'New-Snip', 'Add-Snip', 'Remove-Snip',
        'Edit-Snip', 'Invoke-Snip', 'Copy-Snip', 'Set-SnipTag',
        'Export-SnipCollection', 'Import-SnipCollection',
        'Get-GistList', 'Get-Gist', 'Import-Gist', 'Export-Gist',
        'Invoke-Gist', 'Sync-Gist',
        'Get-GitLabSnipList', 'Get-GitLabSnip', 'Import-GitLabSnip', 'Export-GitLabSnip',
        'Publish-Snip', 'Sync-SharedSnips',
        'Install-PSSnips', 'Uninstall-PSSnips',
        'Start-SnipManager',
        'Get-SnipHistory', 'Restore-Snip', 'Test-Snip',
        'snip'
    )

    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('snippets','gist','github','productivity','terminal','windows')
            ProjectUri = 'https://github.com/your-org/PSSnips'
        }
    }
}
