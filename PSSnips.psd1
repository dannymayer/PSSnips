@{
    RootModule        = 'PSSnips.psm1'
    ModuleVersion = '3.2.0'
    GUID              = 'f3a7c2b1-84e9-4d56-a021-6c3e9f182b47'
    Author            = 'MayerMediaCo'
    CompanyName       = 'MayerMediaCo'
    Copyright         = 'Copyright (c) 2026 MayerMediaCo. Licensed under the MIT License.'
    Description       = 'A terminal-first PowerShell snippet manager with GitHub Gist, GitLab, and Bitbucket integration. Store, search, tag, pin, version, edit, and run local code snippets. Features WSL2/PSRemoting/SQL execution, scheduled tasks, snippet templates, ratings, audit logging, shared team storage, backup/restore, VS Code sync, fuzzy finder, Windows Terminal integration, and an interactive TUI. Requires PowerShell 7.0 or later.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport = @(
        'Initialize-PSSnips',
        'Get-SnipConfig', 'Set-SnipConfig',
        'Get-Snip', 'Show-Snip', 'New-Snip', 'Add-Snip', 'Remove-Snip',
        'Edit-Snip', 'Invoke-Snip', 'Copy-Snip', 'Set-SnipTag',
        'Get-SnipHistory', 'Restore-Snip', 'Test-Snip',
        'Export-SnipCollection', 'Import-SnipCollection', 'Compare-SnipCollection',
        'Get-GistList', 'Get-Gist', 'Import-Gist', 'Export-Gist', 'Invoke-Gist', 'Sync-Gist',
        'Get-GitLabSnipList', 'Get-GitLabSnip', 'Import-GitLabSnip', 'Export-GitLabSnip',
        'Get-BitbucketSnipList', 'Import-BitbucketSnip', 'Export-BitbucketSnip', 'Sync-BitbucketSnips',
        'Get-RemoteSnip', 'Sync-RemoteSnip',
        'Publish-Snip', 'Sync-SharedSnips',
        'Install-PSSnips', 'Uninstall-PSSnips',
        'Start-SnipManager',
        'Invoke-SnipCLI',
        'Get-StaleSnip', 'Get-SnipStats', 'Export-VSCodeSnips', 'Invoke-FuzzySnip',
        'Add-SnipTerminalProfile',
        'Get-SnipAuditLog',
        'Set-SnipRating', 'Add-SnipComment',
        'New-SnipFromTemplate', 'Get-SnipTemplate',
        'New-SnipSchedule', 'Get-SnipSchedule', 'Remove-SnipSchedule',
        'Initialize-SnipPreCommitHook',
        'Sync-SnipMetadata',
        'Register-SnipEvent', 'Unregister-SnipEvent',
        'Invoke-SnipLint', 'Test-SnipLint',
        'Sync-SnipRepo',
        'Set-SnipReadLineKey'
    )

    AliasesToExport   = @('snip')
    CmdletsToExport   = @()
    VariablesToExport = @()
    FormatsToProcess  = @('PSSnips.Format.ps1xml')

    FileList = @(
        'PSSnips.psm1',
        'PSSnips.psd1',
        'PSSnips.Format.ps1xml',
        'Private\Data.ps1',
        'Private\Logging.ps1',
        'Private\Parsing.ps1',
        'Private\EventDispatch.ps1',
        'Private\IO.ps1',
        'Private\DataStore.ps1',
        'Private\Credentials.ps1',
        'Private\ApiClients.ps1',
        'Private\Fts.ps1',
        'Private\Audit.ps1',
        'Private\Helpers.ps1',
        'Private\Highlighting.ps1',
        'Private\Completers.ps1',
        'Private\Providers\RemoteProvider.ps1',
        'Private\Providers\GitHubProvider.ps1',
        'Private\Providers\GitLabProvider.ps1',
        'Private\Providers\BitbucketProvider.ps1',
        'Private\ProviderFactory.ps1',
        'Public\Config.ps1',
        'Public\Core.ps1',
        'Public\Backup.ps1',
        'Public\GitHub.ps1',
        'Public\GitLab.ps1',
        'Public\Bitbucket.ps1',
        'Public\Remote.ps1',
        'Public\Sharing.ps1',
        'Public\Profile.ps1',
        'Public\TUI.ps1',
        'Public\Dispatcher.ps1',
        'Public\Analytics.ps1',
        'Public\Templates.ps1',
        'Public\Linting.ps1',
        'Public\Compare.ps1',
        'Public\GitSync.ps1',
        'Public\PSReadLine.ps1'
    )

    PrivateData = @{
        PSData = @{
            Tags             = @(
                'snippets', 'snippet-manager', 'gist', 'github', 'github-gist', 'gitlab', 'bitbucket',
                'productivity', 'terminal', 'windows', 'cli', 'code-snippets',
                'devtools', 'developer-tools', 'powershell', 'tui',
                'code-reuse', 'automation', 'scripting', 'version-control', 'team',
                'wsl', 'remoting', 'sql', 'audit', 'templates', 'scheduling'
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
