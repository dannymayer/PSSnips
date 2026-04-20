# Changelog

All notable changes to [PSSnips](https://github.com/dannymayer/PSSnips) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] — 2026-04-20

### Fixed

- **PowerShell minimum version** declared as 7.0; drops PS 5.1 support
  (`PowerShellVersion = '7.0'`, `CompatiblePSEditions = @('Core')`).
- **Unicode encoding fix** in CI workflow files to ensure consistent UTF-8
  output on Windows runners.
- **PSScriptAnalyzerSettings.psd1** added to repository to enforce consistent
  static analysis rules across local and CI runs.
- **SupportsShouldProcess** (`-WhatIf` / `-Confirm`) added to `Set-SnipConfig`,
  `New-Snip`, `Set-SnipTag`, and `Start-SnipManager`.
- **Private TUI helper functions** renamed from unapproved verbs to approved
  verbs: `Draw-List` → `Write-SnipList`, `Draw-Detail` → `Write-SnipDetail`.

---

## [1.0.0] — 2026-01-01

### Added

#### Core Snippet Management
- `New-Snip` — Create a named snippet and open it in the configured editor
- `Add-Snip` — Import a snippet from a file path, clipboard, or pipeline string
- `Show-Snip` — Display snippet content with syntax-highlighted output
- `Get-Snip` — List and search snippets by name, description, tag, or content
- `Edit-Snip` — Open an existing snippet in the configured editor
- `Remove-Snip` — Delete a snippet with optional confirmation prompt
- `Copy-Snip` — Copy snippet content to the Windows clipboard
- `Set-SnipTag` — Add, remove, or replace tags on a snippet

#### Snippet Features
- Snippet tagging, pinning (favourites), and full-text content search
- Run history tracking (`runCount`, `lastRun`) with sortable listings via `Get-Snip -Sort`
- Snippet versioning: `Get-SnipHistory` to view past versions, `Restore-Snip` to roll back
- Template variable substitution using `{{PLACEHOLDER}}` syntax (prompts at run time)
- Snippet chaining via `Invoke-Snip -Pipeline` to pass output to the next snippet
- PSScriptAnalyzer lint integration via `Test-Snip`
- SHA-256 duplicate detection prevents accidental re-import of identical content

#### GitHub Gist Integration
- `Get-GistList` — List your GitHub Gists
- `Get-Gist` — Display a Gist by ID
- `Import-Gist` — Download a Gist and save it as a local snippet
- `Export-Gist` — Push a local snippet to GitHub as a new Gist
- `Invoke-Gist` — Run a Gist directly without saving locally
- `Sync-Gist` — Bidirectional sync between a local snippet and its upstream Gist

#### GitLab Snippet Integration
- `Get-GitLabSnipList` — List your GitLab snippets
- `Get-GitLabSnip` — Display a GitLab snippet by ID
- `Import-GitLabSnip` — Import a GitLab snippet as a local snippet
- `Export-GitLabSnip` — Push a local snippet to GitLab

#### Team / Shared Storage
- `Publish-Snip` — Copy a snippet to a shared UNC or local team path
- `Sync-SharedSnips` — Pull new/updated snippets from the shared team store

#### Backup & Restore
- `Export-SnipCollection` — Archive all snippets and configuration to a zip file
- `Import-SnipCollection` — Restore snippets from an archive

#### Profile Integration
- `Install-PSSnips` — Add the PSSnips import line to the current PowerShell profile
- `Uninstall-PSSnips` — Remove the PSSnips import line from the profile

#### Interactive TUI
- `Start-SnipManager` (alias: `snip`) — Full-screen terminal UI with arrow-key navigation,
  live search, preview pane, and keyboard shortcuts for all common operations

#### CLI Dispatcher
- `Invoke-SnipCLI` (alias: `snip`) — Single entry-point that routes sub-commands
  (`list`, `new`, `add`, `show`, `edit`, `run`, `rm`, `copy`, `tag`, `search`,
  `config`, `gist *`, `help`) to the appropriate PSSnips cmdlets

#### Runtime Support
- Executes PS1, Python, JavaScript, Batch, Bash, Ruby, and Go snippets via `Invoke-Snip`
- PlatyPS-generated external help (`en-US/PSSnips-help.xml`)
- Tab-completion for snippet names on all relevant commands

### Changed
- Initial release — no prior version to compare against

### Fixed
- Initial release — no prior version to compare against

---

[1.0.1]: https://github.com/dannymayer/PSSnips/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/dannymayer/PSSnips/releases/tag/v1.0.0
