@{
    RootModule        = 'PSSnips.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f3a7c2b1-84e9-4d56-a021-6c3e9f182b47'
    Author            = 'MayerMediaCo'
    CompanyName       = 'MayerMediaCo'
    Copyright         = 'Copyright (c) 2026 MayerMediaCo. Licensed under the MIT License.'
    Description       = 'A terminal-first PowerShell snippet manager with GitHub Gist and GitLab integration. Store, search, tag, pin, version, edit, and run local code snippets. Features shared team storage, backup/restore, PSScriptAnalyzer lint, template variables, snippet chaining, and an interactive TUI. Requires PowerShell 7.0 or later.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @(
        'Initialize-PSSnips',
        'Get-SnipConfig', 'Set-SnipConfig',
        'Get-Snip', 'Show-Snip', 'New-Snip', 'Add-Snip', 'Remove-Snip',
        'Edit-Snip', 'Invoke-Snip', 'Copy-Snip', 'Set-SnipTag',
        'Get-SnipHistory', 'Restore-Snip', 'Test-Snip',
        'Export-SnipCollection', 'Import-SnipCollection',
        'Get-GistList', 'Get-Gist', 'Import-Gist', 'Export-Gist', 'Invoke-Gist', 'Sync-Gist',
        'Get-GitLabSnipList', 'Get-GitLabSnip', 'Import-GitLabSnip', 'Export-GitLabSnip',
        'Publish-Snip', 'Sync-SharedSnips',
        'Install-PSSnips', 'Uninstall-PSSnips',
        'Start-SnipManager',
        'Invoke-SnipCLI'
    )

    AliasesToExport   = @('snip')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags             = @(
                'snippets', 'snippet-manager', 'gist', 'github', 'github-gist', 'gitlab',
                'productivity', 'terminal', 'windows', 'cli', 'code-snippets',
                'devtools', 'developer-tools', 'powershell', 'tui',
                'code-reuse', 'automation', 'scripting', 'version-control', 'team'
            )
            LicenseUri       = 'https://github.com/dannymayer/PSSnips/blob/main/LICENSE'
            ProjectUri       = 'https://github.com/dannymayer/PSSnips'
            IconUri          = 'https://raw.githubusercontent.com/dannymayer/PSSnips/main/assets/icon.png'
            ReleaseNotes     = @'
## 1.0.0 — Initial Release

### Features
- Local snippet CRUD: New-Snip, Add-Snip, Show-Snip, Get-Snip, Edit-Snip, Remove-Snip, Copy-Snip
- Snippet tagging, pinning (favourites), and full-text content search
- Run history tracking (runCount, lastRun) with sortable listings
- Snippet versioning with Get-SnipHistory and Restore-Snip
- Template variable substitution ({{PLACEHOLDER}} syntax)
- Snippet chaining (Invoke-Snip -Pipeline)
- PSScriptAnalyzer integration (Test-Snip)
- GitHub Gist integration: list, get, import, export, invoke, sync
- GitLab snippet integration: list, get, import, export
- Shared team storage via UNC/local path (Publish-Snip, Sync-SharedSnips)
- Backup and restore (Export-SnipCollection, Import-SnipCollection)
- Profile integration (Install-PSSnips, Uninstall-PSSnips)
- SHA-256 duplicate detection on new snippets
- Interactive TUI with arrow-key navigation (Start-SnipManager / snip)
- Supports PS1, Python, JavaScript, Batch, Bash, Ruby, Go execution
- PlatyPS-generated external help (en-US/PSSnips-help.xml)
'@
            Prerelease       = ''
        }
    }
}
