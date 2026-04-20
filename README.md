# PSSnips — Terminal-First PowerShell Snippet Manager

**A fast, keyboard-driven snippet manager for PowerShell 7.0+ on Windows.**

[![PSGallery Version](https://img.shields.io/powershellgallery/v/PSSnips?label=PSGallery&logo=powershell)](https://www.powershellgallery.com/packages/PSSnips)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

## Requirements

- **PowerShell 7.0+** (`pwsh.exe` — PowerShell Core)
- **Windows** (uses Windows clipboard APIs, `~\.pssnips\` data path, and Windows Task Scheduler for scheduling features)

---

## Quick Start

```powershell
Install-Module PSSnips -Scope CurrentUser
Install-PSSnips           # adds Import-Module PSSnips to $PROFILE

snip                      # launch the interactive TUI
snip new deploy           # create your first snippet
snip help                 # show all commands
```

---

> [!NOTE]
> ## What's New in v2.0
>
> **Breaking change:** `Get-Snip` now returns `PSSnips.SnippetInfo` typed objects instead of raw `PSCustomObject`. Scripts that assume untyped hashtable output must be updated.
>
> **New in v2.0:**
> - **Typed output** — `Get-Snip` returns `PSSnips.SnippetInfo` objects with `TagList [string[]]`, `ModifiedDate [datetime]`, `Language`, `Description`, `ContentHash`, and `GistUrl` properties. Enables pipeline-native filtering and sorting.
> - **Layered config** (#26) — 4-layer resolution: env vars → workspace config → user config → module defaults. Workspace config (`.pssnips/config.json`) can be committed to source control.
> - **Event hooks** (#27) — Register scriptblock handlers for `SnipCreated`, `SnipEdited`, `SnipDeleted`, `SnipExecuted`, and `SnipPublished` events.

---

## Installation

### PowerShell Gallery (recommended)

```powershell
Install-Module PSSnips -Scope CurrentUser
```

### Manual

```powershell
Import-Module "C:\path\to\PSSnips\PSSnips.psd1"
```

> Tip: Run `Install-PSSnips` after importing to add the module to your `$PROFILE` permanently. Run `Uninstall-PSSnips` to remove it.

---

## Commands Reference

### Interactive TUI

```powershell
snip          # or: snip ui
```

| Key | Action |
|-----|--------|
| `↑` `↓` | Navigate list |
| `Enter` / `→` | Open detail view |
| `Esc` / `←` / `Backspace` | Go back |
| `/` | Incremental search / filter |
| `q` | Quit |

Pinned snippets (★) sort to the top. Languages are color-coded in the list view.

---

### Core Snippet Commands

```powershell
# Create (opens in editor)
New-Snip deploy
New-Snip deploy -Language ps1 -Description 'Azure deploy script' -Tags 'azure','devops'
Add-Snip loader -Path .\loader.py
Add-Snip my-note -Clip -Language md           # from clipboard
Get-Content .\script.ps1 | Add-Snip my-script # from pipeline

# Read
Show-Snip deploy                              # formatted display
Get-Snip                                      # returns PSSnips.SnippetInfo[]
Get-Snip deploy                               # single snippet object
Get-Snip | Where-Object { $_.TagList -contains 'azure' }
Get-Snip | Sort-Object ModifiedDate -Descending
Get-Snip -Shared                              # list from shared store

# Update
Edit-Snip deploy                              # opens in editor
Edit-Snip deploy -Editor nvim

# Delete
Remove-Snip deploy
Remove-Snip deploy -Force                     # skip confirmation

# Clipboard
Copy-Snip deploy
```

---

### Tag Management

```powershell
Set-SnipTag deploy -Tags 'azure','devops'     # replace all tags
Set-SnipTag deploy -Add 'prod'                # append tag
Set-SnipTag deploy -Remove 'devops'           # remove tag
Set-SnipTag deploy -Pin                       # pin (★ sorts first)
Set-SnipTag deploy -Unpin
```

---

### Execution

```powershell
Invoke-Snip deploy                            # run by file extension
Invoke-Snip deploy -- -Verbose                # pass arguments
Invoke-Snip template -Variables @{ ENV='prod'; REGION='eastus' }   # fill {{PLACEHOLDER}} vars
Invoke-Snip -Pipeline snippet1,snippet2       # chain execution
```

#### Supported Runners

| Extension | Language | Runner |
|-----------|----------|--------|
| `.ps1` | PowerShell | Built-in (`pwsh`) |
| `.py` | Python | `python` |
| `.js` | JavaScript | `node` |
| `.bat` / `.cmd` | Batch | `cmd /c` |
| `.sh` | Bash / Shell | `bash` (WSL) |
| `.rb` | Ruby | `ruby` |
| `.go` | Go | `go run` |

---

### Templates

```powershell
New-SnipFromTemplate -Template azure-function -Name my-func -Variables @{ FuncName='HttpTrigger' }
Get-SnipTemplate      # list available templates
```

New snippets created via `New-Snip` default to the CBH block template for `.ps1`/`.psm1` files.

---

### Versioning & History

Every `Edit-Snip` save creates a timestamped version automatically.

```powershell
Get-SnipHistory deploy              # list all saved versions
Restore-Snip deploy -Version 3     # restore to version 3
```

---

### Backup & Restore

```powershell
Export-SnipCollection -Path .\backup.zip        # ZIP of all snippets + index
Import-SnipCollection -Path .\backup.zip        # full restore
Import-SnipCollection -Path .\backup.zip -Merge # merge; existing snippets are kept
```

---

### Analytics & Maintenance

```powershell
Get-SnipStats                        # run counts, top snippets, language breakdown
Get-StaleSnip -Days 90               # snippets unused for > 90 days
Get-SnipAuditLog                     # structured audit trail (create/edit/delete/execute)
Test-Snip deploy                     # run PSScriptAnalyzer on a .ps1 snippet inline
Export-VSCodeSnips                   # export all snippets as VS Code snippets.json
```

---

### Ratings & Comments

```powershell
Set-SnipRating deploy -Rating 5          # 1–5 stars stored in index
Add-SnipComment deploy -Comment 'Works great in prod'   # timestamped comment
```

---

### Fuzzy Finder

```powershell
Invoke-FuzzySnip azure    # fuzzy search name/tag/description; uses fzf if available, falls back to numbered menu
```

---

### Scheduling

Uses Windows Task Scheduler.

```powershell
New-SnipSchedule deploy -Trigger Daily -At '08:00'
Get-SnipSchedule
Remove-SnipSchedule deploy
```

---

### Profile & Terminal Integration

```powershell
Install-PSSnips                    # adds Import-Module PSSnips to $PROFILE
Uninstall-PSSnips                  # removes the import line
Add-SnipTerminalProfile            # adds a Windows Terminal profile that launches snip
Initialize-SnipPreCommitHook       # installs a Git pre-commit hook: runs Test-Snip on staged .ps1 snippets
```

---

### PowerShell CBH Metadata Integration

For `.ps1` and `.psm1` snippets, PSSnips auto-extracts:
- `.SYNOPSIS` → `Description`
- `.NOTES Tags:` → `Tags`

```powershell
Sync-SnipMetadata              # bulk sync CBH → index for all ps1/psm1 snippets
Sync-SnipMetadata -Overwrite   # overwrite existing metadata
```

---

### Duplicate Detection

SHA-256 `ContentHash` is stored in the index. `New-Snip` warns when content already exists.

```powershell
New-Snip deploy-v2 -IgnoreDuplicate   # suppress duplicate warning
```

---

## GitHub Gist Integration

### Setup

Generate a Personal Access Token at <https://github.com/settings/tokens> with the `gist` scope, then:

```powershell
Set-SnipConfig -GitHubToken ghp_yourTokenHere
Set-SnipConfig -GitHubUser your-github-username
```

Or via environment variable:

```powershell
$env:PSSNIPS_GITHUB_TOKEN = 'ghp_yourTokenHere'
$env:PSSNIPS_GITHUB_USER  = 'your-github-username'
```

### Commands

```powershell
Get-GistList                                     # list your gists
Get-GistList deploy                              # filter by name
Get-Gist abc123def456                            # view a gist
Import-Gist abc123def456                         # import as local snippet
Import-Gist abc123def456 -Name my-local-name
Export-Gist deploy                               # push local snippet to Gist
Export-Gist deploy -Public                       # public gist
Invoke-Gist abc123def456                         # run a gist without importing
Sync-Gist deploy                                 # pull latest from GitHub
Sync-Gist deploy -Push                           # push local → GitHub
```

---

## GitLab Snippet Integration

### Setup

Generate a GitLab Personal Access Token with `api` scope, then:

```powershell
Set-SnipConfig -GitLabToken glpat_yourTokenHere
Set-SnipConfig -GitLabUrl 'https://gitlab.example.com'   # for self-hosted instances
```

Or via environment variables:

```powershell
$env:PSSNIPS_GITLAB_TOKEN = 'glpat_yourTokenHere'
$env:PSSNIPS_GITLAB_URL   = 'https://gitlab.example.com'
```

### Commands

```powershell
Get-GitLabSnipList
Get-GitLabSnip <id>
Import-GitLabSnip <id>
Export-GitLabSnip deploy
```

---

## Bitbucket Snippet Integration

```powershell
Get-BitbucketSnipList
Import-BitbucketSnip <id>
Export-BitbucketSnip deploy
Sync-BitbucketSnips
```

---

## Team Shared Storage

Share snippets via a UNC path or any local/network directory.

```powershell
Set-SnipConfig -SharedSnippetsDir '\\server\share\snippets'

Publish-Snip deploy               # copy to shared dir, updates shared-index.json
Sync-SharedSnips                  # pull from shared dir into local index
Get-Snip -Shared                  # list snippets from the shared store
```

---

## Configuration

PSSnips resolves settings in this priority order (highest wins):

| Layer | Source | Description |
|-------|--------|-------------|
| 1 | Environment variables | Per-session or CI/CD overrides |
| 2 | Workspace config | `.pssnips\config.json` in cwd; can be committed |
| 3 | User config | `~\.pssnips\config.json`; written by `Set-SnipConfig` |
| 4 | Module defaults | Built-in fallbacks |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `PSSNIPS_DIR` | Override the snippets storage directory |
| `PSSNIPS_EDITOR` | Default editor (`edit`, `nvim`, `code`, `notepad`) |
| `PSSNIPS_DEFAULT_LANG` | Default language extension for new snippets |
| `PSSNIPS_GITHUB_TOKEN` | GitHub PAT for Gist integration |
| `PSSNIPS_GITHUB_USER` | GitHub username |
| `PSSNIPS_GITLAB_TOKEN` | GitLab PAT |
| `PSSNIPS_GITLAB_URL` | GitLab base URL (self-hosted) |
| `PSSNIPS_SHARED_DIR` | Shared snippets UNC/local path |
| `PSSNIPS_WORKSPACE` | Path to workspace root (overrides cwd detection) |

### Workspace Config

Place `.pssnips\config.json` in your project root. Commit it to source control to share settings with your team.

```powershell
Set-SnipConfig -Scope Workspace -DefaultLang ps1 -Editor nvim
```

```json
{
  "defaultLang": "ps1",
  "editor": "nvim"
}
```

### User Config

```powershell
Set-SnipConfig -Editor nvim
Set-SnipConfig -DefaultLang py
Set-SnipConfig -SnippetsDir 'D:\MySnippets'
Set-SnipConfig -ConfirmDelete $false

Get-SnipConfig               # show resolved config
Get-SnipConfig -ShowSources  # show which layer each value came from
```

---

## Event Hooks

Register scriptblock handlers that fire on snippet lifecycle events.

```powershell
Register-SnipEvent -Event <name> -Handler { param($e) ... }   # returns registration Id
Unregister-SnipEvent -Event <name> -Id <id>
```

### Available Events

| Event | Extra Keys in `$e` |
|-------|--------------------|
| `SnipCreated` | — |
| `SnipEdited` | — |
| `SnipDeleted` | — |
| `SnipExecuted` | `Duration` |
| `SnipPublished` | `Provider`, `Url` |

### Example: Audit Log in $PROFILE

```powershell
# Log all executions to a file
Register-SnipEvent -Event SnipExecuted -Handler {
    param($e)
    "[$(Get-Date -f s)] Executed '$($e.Name)' in $($e.Duration.TotalSeconds)s" |
        Add-Content "$HOME\snip-audit.log"
}
```

### Example: Slack Webhook Notification

```powershell
# Post to Slack when a snippet is published
Register-SnipEvent -Event SnipPublished -Handler {
    param($e)
    $body = @{ text = "📦 Snippet *$($e.Name)* published to $($e.Provider): $($e.Url)" } | ConvertTo-Json
    Invoke-RestMethod -Uri $env:SLACK_WEBHOOK_URL -Method Post -Body $body -ContentType 'application/json'
}
```

> Handlers added in `$PROFILE` persist across sessions. Use `Unregister-SnipEvent` to remove them.

---

## Editor Priority

PSSnips selects the first available editor:

| Priority | Editor | Command | Notes |
|----------|--------|---------|-------|
| 1 | Microsoft Edit | `edit.exe` | Built-in terminal editor (Windows 11 24H2+) |
| 2 | Neovim | `nvim` | |
| 3 | VS Code | `code` | |
| 4 | Notepad | `notepad` | Always available fallback |

Override per-command: `Edit-Snip deploy -Editor code`  
Override permanently: `Set-SnipConfig -Editor nvim`

---

## Data Layout

```
~\.pssnips\
├── config.json          # user config
├── index.json           # snippet metadata + run history
├── audit.json           # audit log
├── snippets\            # snippet files (any extension)
│   ├── deploy.ps1
│   └── parse-csv.py
└── history\             # timestamped version backups per snippet
    └── deploy\
        └── 20260101120000.ps1
```

**Workspace config** (per-project, optional — safe to commit):

```
<project root>\
└── .pssnips\
    └── config.json      # workspace overrides
```

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow the existing module structure (`Public\`, `Private\`, `PSSnips.psd1`).
3. Run `Test-Snip` and `PSScriptAnalyzer` before submitting a PR.
4. Open a pull request against `main` — please reference any related issue.

---

## License

MIT © [MayerMediaCo](https://www.powershellgallery.com/profiles/MayerMediaCo)
