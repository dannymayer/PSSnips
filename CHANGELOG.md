# Changelog

All notable changes to [PSSnips](https://github.com/dannymayer/PSSnips) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [3.1.0] — 2026-05-01

### Added

- **`Sync-SnipRepo`** (`Public\GitSync.ps1`) — git-backed snippet repository sync.
  - `-Pull`, `-Push`, `-Status` modes; default is bidirectional pull-then-push.
  - `-Remote <url>` one-shot URL override; reads `SnipRepoUrl`/`SnipRepoDir` from config.
  - Auto-clones if `SnipRepoDir` does not exist. Graceful error if `git` not in PATH.
  - `SupportsShouldProcess` gates all write operations. Returns `[PSCustomObject]` with
    `Status`, `Branch`, `Changes`.

- **`Compare-SnipCollection`** (`Public\Compare.ps1`) — diff preview before import.
  - `-Path <zip>` accepts an `Export-SnipCollection` archive.
  - Classifies each snippet as **Added**, **Modified**, **Unchanged**, or **LocalOnly**.
  - Displays formatted preview table with per-category counts.
  - `-PassThru` returns structured `[PSCustomObject]` array for scripting.
  - Temp directory cleaned up in `try/finally` even on error.

- **Namespace prefix** (`ns/name` hierarchy, no schema change).
  - `Get-Snip -Namespace <prefix>` filters by first `/`-delimited segment of snippet name.
  - `Namespace` property added to all `Get-Snip` output objects.
  - TUI (`Start-SnipManager`) displays dim `── <namespace> ──` group headers when ≥2
    distinct namespaces are present in the filtered list.
  - `Register-ArgumentCompleter` for `Get-Snip -Namespace` tab-completes from live index.
  - Private helper `script:Get-SnipNamespace` added to `Private\Helpers.ps1`.

- **Centralized shared audit log**.
  - `script:Append-SharedAudit` helper (`Private\Audit.ps1`) appends entries to
    `<SharedSnippetsDir>/shared-audit.json` on every successful publish or sync.
  - Entry fields: `timestamp` (ISO 8601), `operation` (`Publish`/`Sync`), `snippetName`,
    `user` (`DOMAIN\username`), `machine` (`$env:COMPUTERNAME`).
  - `Publish-Snip` and `Sync-SharedSnips` call `Append-SharedAudit` after success.
  - `Get-SnipAuditLog -Shared` switch reads and returns the shared log as `[PSCustomObject]`
    array; warns if `SharedSnippetsDir` is not configured.

## [3.0.0] — 2026-04-21

### Added

- **Provider/Adapter pattern for remote sources (v3.0 Item 4)**
  - `RemoteProvider` abstract base class (`Private\Providers\RemoteProvider.ps1`) with a
    standard interface: `IsConfigured`, `ListRemote`, `GetRemoteById`, `CreateRemote`,
    `UpdateRemote`, `DeleteRemote`, `SyncRemote`.
  - `GitHubProvider` concrete class — delegates GitHub Gist API calls via
    `$script:_CallGitHubDelegate` to keep class methods compatible with module scope.
  - `GitLabProvider` concrete class — delegates GitLab Snippets API calls via
    `$script:_CallGitLabDelegate`; `GetRemoteById` returns snippet object with
    `RawContent` property added.
  - `BitbucketProvider` concrete class — uses `PSCredential` (Basic auth) and calls
    `Invoke-RestMethod` directly; `CreateRemote`/`UpdateRemote` throw
    `NotImplementedException` (multipart upload deferred to v3.1).
  - `script:Get-RemoteProvider` factory (`Private\ProviderFactory.ps1`) constructs
    the correct provider for 'GitHub', 'GitLab', or 'Bitbucket' from current config.
  - Delegate scriptblocks `$script:_CallGitHubDelegate` and `$script:_CallGitLabDelegate`
    added to `Private\ApiClients.ps1`.
- **`Get-RemoteSnip`** — unified public function to list or retrieve snippets from any
  supported provider. Supports `-Provider`, `-Id`, and `-Filter` parameters.
- **`Sync-RemoteSnip`** — unified public function to push/pull/bidirectionally sync a
  named local snippet with a remote provider. Falls back to provider-specific sync
  functions until `SyncRemote` is implemented in the provider classes (v3.1 TODO).

### Changed

- **`Get-GistList`** — now creates a `GitHubProvider` to fetch gists; filtering is
  performed in the provider, `-Count` trims client-side.
- **`Get-Gist`, `Import-Gist`, `Invoke-Gist`** — now use `script:Get-RemoteProvider`
  and `GetRemoteById` instead of calling `script:CallGitHub` directly.
- **`Export-Gist`** — uses provider `CreateRemote`/`UpdateRemote` for the API call;
  local index update logic remains in the wrapper.
- **`Get-GitLabSnipList`** — now uses `script:Get-RemoteProvider` and `ListRemote`.
- **`Get-GitLabSnip`, `Import-GitLabSnip`** — use `GetRemoteById` (which includes
  `RawContent`) instead of calling both metadata and raw endpoints separately.
- **`Export-GitLabSnip`** — uses provider `CreateRemote`/`UpdateRemote`.
- **`Get-BitbucketSnipList`** — now uses `script:Get-RemoteProvider` and `ListRemote`;
  returned objects use PascalCase property names (`Id`, `Title`, `IsPrivate`, etc.).
  `-Role` filter still re-queries the API directly.
- **`Import-BitbucketSnip`** — uses `BitbucketProvider.GetRemoteById` for the metadata
  fetch; per-file content fetch still done in the wrapper.
- **`Export-BitbucketSnip`** — adds `IsConfigured()` guard via provider; multipart
  upload logic is unchanged.
- Version bumped to **3.0.0**.

### Architecture notes

- v3.0 Items 1–3 (module split, `SnippetMetadata`, `SnipRepositoryBase`/`JsonSnipRepository`)
  were completed in prior commits. Item 4 (provider/adapter pattern) completes v3.0.
- `SyncRemote` in all three provider classes currently throws `NotImplementedException`.
  `Sync-RemoteSnip` catches this and delegates to the provider-specific sync functions
  (`Sync-Gist`, `Export/Import-GitLabSnip`, `Sync-BitbucketSnips`). Full implementation
  is tracked as v3.1 work.

---

## [2.2.0] - 2026-04-21
### Added
- `Show-Snip -Highlighted` — ANSI syntax highlighting via PowerShell built-in tokenizer (zero dependencies)
- `Show-Snip -Format Auto|Bat|Plain` — `bat` integration with automatic fallback to tokenizer
- `Invoke-SnipLint` — runs PSScriptAnalyzer on a snippet and displays a diagnostic table
- `Test-SnipLint` — returns pass/fail boolean for CI pipeline use; PS1/PSM1/PSD1 only
## [2.1.0] - 2026-04-20
### Added
- `{{VAR:default}}` inline template defaults — placeholders now support `:default` fallback syntax
- Environment variable auto-injection for templates — resolution order: `-Variables` → `$env:VARNAME` → inline default → interactive prompt
- `Invoke-Snip -WhatIf` dry-run — displays resolved snippet content without executing
- Author/creator metadata — `createdBy`/`updatedBy` fields in index; `Author` property on `PSSnips.SnippetInfo`; `Get-Snip -Author` filter
## [2.0.0] — 2026-04-20

### Breaking Changes

- **`Get-Snip` output type** — The function no longer writes a coloured table to the
  host. Display is now handled entirely by `PSSnips.Format.ps1xml`, which is
  registered in the module manifest and applied automatically. Scripts that relied on
  `Write-Host` side-effects from `Get-Snip` should instead pipe to `Format-Table` or
  use the returned objects directly. The `[OutputType]` annotation is now
  `'PSSnips.SnippetInfo'` (a named type) rather than `[PSCustomObject]`.

### Added

- **Typed output (`PSSnips.SnippetInfo`)** — `Get-Snip` now stamps every returned
  object with `PSTypeName = 'PSSnips.SnippetInfo'`. New richly-typed properties:
  - `Language` — full language name (alias for `Lang`)
  - `TagList` — `[string[]]` array enabling `-contains` filtering
  - `ModifiedDate` — `[datetime]` or `$null` for typed sorting
  - `Description` — alias for `Desc`
  - `ContentHash` — SHA-256 hash from the index
  - `GistUrl` — full Gist URL when linked
- **`PSSnips.Format.ps1xml`** — new format file registered via `FormatsToProcess`.
  Renders a `TableControl` with pin indicator (★), NAME, LANG, GIST, TAGS, RUNS,
  and MODIFIED columns using `<AutoSize/>`.
- **Layered configuration (#26)** — Config is now resolved in priority order:
  environment variables → workspace config → user config → module defaults.
  - Environment variables: `PSSNIPS_DIR`, `PSSNIPS_EDITOR`, `PSSNIPS_DEFAULT_LANG`,
    `PSSNIPS_GITHUB_TOKEN`, `PSSNIPS_GITHUB_USER`, `PSSNIPS_GITLAB_TOKEN`,
    `PSSNIPS_GITLAB_URL`, `PSSNIPS_SHARED_DIR`, `PSSNIPS_WORKSPACE`
  - Workspace config: `.pssnips/config.json` in the current directory (or path set by
    `$env:PSSNIPS_WORKSPACE`). Ideal for per-project settings.
  - `Set-SnipConfig -Scope Workspace` writes to the workspace config file.
  - `Get-SnipConfig -ShowSources` displays which layer each value was resolved from.
- **Event/hook system (#27)** — Subscribe to PSSnips lifecycle events:
  - `Register-SnipEvent -Event <name> -Handler { param($e) ... }` — attaches a
    script block to a named event. Returns a registration Id.
  - `Unregister-SnipEvent -Event <name> -Id <id>` — removes a handler.
  - Supported events: `SnipCreated`, `SnipEdited`, `SnipDeleted`, `SnipExecuted`
    (with `Duration` timing), `SnipPublished` (GitHub/GitLab/Bitbucket).
  - Handlers are synchronous, fire after each operation, and swallow errors via
    `Write-Verbose` so a broken handler never disrupts normal usage.

### Fixed

- **TUI detail-view overdraw** — Transitioning from list view to snippet detail view
  now calls `Clear-Host` before rendering, eliminating leftover list rows visible
  behind the detail panel.

---

## [1.2.2] — 2026-04-20

### Fixed

- **TUI Backspace navigation** — Backspace (VK 8) now returns to the list view from
  snippet detail view, consistent with Escape and Left arrow.

### Added

- **CBH metadata integration** — `.ps1` and `.psm1` snippets now use PowerShell
  comment-based help as the authoritative metadata source:
  - New `.ps1` snippet template uses a proper CBH block (`.SYNOPSIS`, `.DESCRIPTION`,
    `.NOTES` with `Tags:` line) instead of plain line comments.
  - `Edit-Snip` — after the editor closes, auto-fills an empty index `description`
    from `.SYNOPSIS` and empty `tags` from `.NOTES Tags:` without prompting.
  - `Add-Snip` — when importing a `.ps1`/`.psm1` file with no `-Description` or
    `-Tags` provided, CBH fields are extracted and stored automatically.
  - `Sync-SnipMetadata` — new public command to retroactively sync all (or a named)
    `.ps1`/`.psm1` snippet's index entry from its CBH. Supports `-Overwrite` to
    replace existing values and `-WhatIf` to preview.

---

## [1.2.0] — 2026-04-20

### Added

- **Bitbucket Snippets provider** — `Get-BitbucketSnipList`, `Import-BitbucketSnip`,
  `Export-BitbucketSnip`, `Sync-BitbucketSnips` via Bitbucket Cloud API v2.0.
  Configure with `Set-SnipConfig -BitbucketUsername` / `-BitbucketAppPassword` or
  `$env:BITBUCKET_USERNAME` / `$env:BITBUCKET_APP_PASSWORD`.
- **WSL2 execution** — `.sh` snippets now prefer WSL2 with automatic Windows→WSL
  mount path translation (`C:\...` → `/mnt/c/...`) and `chmod +x` before run.
  Falls back to Git Bash, then WSL1.
- **PSRemoting** — `Invoke-Snip -ComputerName <string[]> [-Credential <PSCredential>]`
  runs `.ps1` snippets on remote machines via `Invoke-Command`.
- **SQL runner** — `Invoke-Snip myquery.sql -ConnectionString '...'` executes against
  SQL Server (prefers `dbatools`, falls back to `System.Data.SqlClient`). Results
  formatted as table; DML shows rows-affected.
- **Audit logging** — `script:Write-AuditLog` records Create/Edit/Delete/Execute/
  Import/Export operations as NDJSON to `~/.pssnips/audit.log` (10 MB rotation).
  `Get-SnipAuditLog [-Last <int>] [-Operation <string>] [-SnippetName <string>]`
  queries the log.
- **Ratings & Comments** — `Set-SnipRating -Name <n> -Stars <1-5>` stores a rating
  in the index. `Add-SnipComment -Name <n> -Text <string>` appends timestamped
  comments to `~/.pssnips/comments/<name>.json`. `Show-Snip -Comments` displays them.
- **Snippet Templates** — `New-SnipFromTemplate -Template <name> -Name <name>
  [-Variables <hashtable>]` scaffolds snippets from `{{VARIABLE}}` templates.
  Built-ins: `azure-function`, `rest-call`, `k8s-job`. Custom templates in
  `~/.pssnips/templates/`. `Get-SnipTemplate` lists all available templates.
- **Scheduled execution** — `New-SnipSchedule -Name <n> -Schedule Daily|Weekly|
  Hourly|OnLogon|OnStartup` registers a Windows Scheduled Task.
  `Get-SnipSchedule` / `Remove-SnipSchedule` for management.
- **Pre-commit hook** — `Initialize-SnipPreCommitHook [-RepoPath <path>] [-WhatIf]`
  installs a git pre-commit hook that runs `Test-Snip` on all staged `.ps1` files.

---

## [1.1.1] — 2026-04-20

### Added

- **`Add-SnipTerminalProfile [-Keybinding <string>] [-Font <string>] [-Path <string>] [-Force] [-WhatIf]`** —
  injects a PSSnips TUI profile, a custom colour scheme (Catppuccin Mocha-inspired
  dark theme), and an optional keybinding (`Ctrl+Alt+S` by default) into Windows
  Terminal's `settings.json`. Auto-detects Stable, Preview, and unpackaged
  installs. Idempotent: warns on re-run unless `-Force` is passed. Fully
  `-WhatIf` / `-Confirm` compatible.

---

## [1.1.0] — 2026-04-20

### Added

- **`Get-StaleSnip [-DaysUnused <int>] [-IncludeNeverRun]`** — lists snippets
  not run in N days (default 90). Displays `DaysIdle` column; never-run
  snippets shown as `∞` with `-IncludeNeverRun`.
- **`Get-SnipStats [-Top <int>] [-SortBy RunCount|LastRun|Name] [-All]`** —
  execution leaderboard aggregated from index `runCount` / `lastRun` metadata.
- **`Export-VSCodeSnips [-Language <ext>] [-OutputDir <path>] [-WhatIf]`** —
  exports the snippet collection to VS Code user snippets JSON format
  (`$env:APPDATA\Code\User\snippets\<lang>.json`). Merges with existing files.
  Auto-detects VS Code Stable and Insiders installs.
- **`Invoke-FuzzySnip [-Action Show|Run|Edit] [-Filter <string>]`** — fuzzy
  snippet picker via `fzf` with in-terminal preview. Falls back to `PSFzf`'s
  `Invoke-Fzf` if raw fzf is unavailable, or to `Get-Snip` if neither is
  installed.

### Performance

- **Module-level index/config cache** — `LoadIdx` and `LoadCfg` return a
  cached in-memory hashtable on repeat calls; dirty flag cleared on every
  `SaveIdx`/`SaveCfg`; reduces per-operation I/O by ~90%.
- **Argument completer TTL cache** — snippet name completions are cached for
  10 seconds and invalidated immediately on any write, eliminating a full
  index deserialise on every `<TAB>` press.
- **TUI single-load optimisation** — `Start-SnipManager` loads the index once
  at startup; `Get-Filtered` uses the in-memory copy; index refreshed only
  after write actions (`n`, `e`, `d`, `g`).
- **Full-text search sidecar cache (`fts-cache.json`)** — `Get-Snip -Content`
  now queries an in-memory FTS index rebuilt on each save instead of reading
  every snippet file from disk. Cache file excluded from git via `.gitignore`.

---

## [1.0.2] — 2026-04-20

### Fixed

- **File locking on `index.json` and `config.json`** — `SaveIdx` and `SaveCfg`
  now acquire an advisory `.lock` file (with 3 s timeout) and write via a
  temp-file → atomic rename, eliminating silent data loss when two sessions
  write concurrently. Same protection applied to `shared-index.json` in
  `Publish-Snip`. Stale `.lock` files are cleaned up on module load.
- **Token security warning** — `Set-SnipConfig -GitHubToken` / `-GitLabToken`
  now emits `Write-Warning` directing users to environment variables instead of
  plain-text storage. New `-SecureStorage` switch encrypts the token with
  Windows DPAPI (`ConvertFrom-SecureString`) and stores it under a `*Secure`
  key; token resolution priority is `$env:` → DPAPI → plain-text.
- **`Get-SnipConfig` token masking** — stored tokens are now displayed as
  `[plain-text]` or `[DPAPI encrypted]` instead of the raw value.
- **`$ErrorActionPreference = 'Stop'` removed from module scope** — setting
  this at module scope could affect the caller's session; per-function
  `try/catch` and `-ErrorAction` flags are sufficient.
- **Test isolation** — `PSSnips.Tests.ps1` no longer directly mutates
  `$script:Defaults['SnippetsDir']`; the test `BeforeAll` now pre-seeds
  `config.json` so `script:InitEnv` picks up the temp path via `LoadCfg`.

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

[1.1.0]: https://github.com/dannymayer/PSSnips/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/dannymayer/PSSnips/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/dannymayer/PSSnips/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/dannymayer/PSSnips/releases/tag/v1.0.0
