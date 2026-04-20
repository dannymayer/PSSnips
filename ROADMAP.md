# PSSnips Roadmap

> **Current version**: 1.0.1  
> **Research basis**: Code review, architecture analysis, feature research, efficiency analysis, documentation review  
> **Scope**: Near-term patches → mid-term feature work → long-term architectural evolution

---

## Executive Summary

PSSnips v1.0.1 is a production-ready, Gallery-published PowerShell snippet manager with solid core functionality: local CRUD, GitHub Gist and GitLab integration, versioned history, team shared storage, interactive TUI, and a comprehensive Pester test suite. The platform is healthy but research has surfaced two **critical data-safety issues** (concurrent write race conditions and plain-text token storage), several high-value efficiency improvements, and a clear architectural evolution path toward a provider-based, class-structured v2.0.

---

## 🔴 Immediate Fixes (v1.0.2 — Patch)

These are correctness and security issues that should be addressed before the next feature release.

### 1. File-Locking on `index.json` Writes — Race Condition
**Source**: Code review, Efficiency analysis  
**Severity**: Critical  
**Problem**: `LoadIdx`/`SaveIdx` perform read-modify-write with no file lock. Two concurrent sessions (or two users on a shared UNC path) will silently lose each other's writes — no error, no warning, silent data loss.  
**Fix**: Implement atomic writes (write to `.tmp`, rename) plus a `.lock` file advisory mutex. The `shared-index.json` used by `Publish-Snip`/`Sync-SharedSnips` has the same vulnerability and needs the same treatment.  
**Effort**: Medium

### 2. Token Security Warning at `Set-SnipConfig`
**Source**: Code review  
**Severity**: High (security)  
**Problem**: GitHub and GitLab tokens are stored in plain-text `~/.pssnips/config.json` with no runtime warning. The help text mentions it but users calling `Set-SnipConfig -GitHubToken` receive no active warning.  
**Fix**: Emit `Write-Warning` at call time directing users to `$env:GITHUB_TOKEN`. Long-term: store via Windows DPAPI (`ConvertTo-SecureString -AsPlainText | ConvertFrom-SecureString`).  
**Effort**: Low → Medium

### 3. Module-Scope `$ErrorActionPreference = 'Stop'` Bleeds to Caller
**Source**: Code review  
**Severity**: Medium  
**Problem**: Setting `$ErrorActionPreference` at module scope can affect the caller's session in certain invocation paths.  
**Fix**: Remove module-level assignment; rely on per-function `try/catch` and `$PSCmdlet` error routing already present throughout the module.  
**Effort**: Low

### 4. Test Isolation — `$script:Defaults` Mutation
**Source**: Code review  
**Severity**: Medium (test brittleness)  
**Problem**: `PSSnips.Tests.ps1` directly mutates `$script:Defaults['SnippetsDir']` rather than relying solely on the config.json written by `InitEnv`. This creates fragile shared state.  
**Fix**: Remove the direct `$script:Defaults` mutation and rely on the test config.json path already being set via `$script:Home`.  
**Effort**: Low

---

## 🟡 v1.1 — Performance & Developer Experience

Quick wins that improve day-to-day usability without architectural changes.

### 5. Module-Level Index/Config Cache
**Source**: Efficiency analysis  
**Problem**: `LoadCfg` and `LoadIdx` are each called 20+ times per module load. A single `New-Snip` with editing triggers 3+ `LoadIdx` calls. A batch import of 100 snippets causes 200–300 filesystem operations.  
**Fix**: Maintain a module-scope `$script:IdxCache` and `$script:CfgCache` hashtable with a dirty flag. Invalidate on `SaveIdx`/`SaveCfg`. This reduces I/O by ~90% with no change to external behavior.  
**Effort**: Medium  
**Impact**: Dramatically faster batch operations; near-instant tab completion on large collections

### 6. Argument Completer TTL Cache
**Source**: Efficiency analysis  
**Problem**: The `snip` argument completer calls `LoadIdx` on every `<TAB>` press, deserializing the full JSON each time. With 1000+ snippets, tab completion becomes noticeably sluggish.  
**Fix**: Cache the completer result in a module-scoped variable with a 10-second TTL and a dirty flag that clears on any write operation.  
**Effort**: Low

### 7. TUI Index Load Optimization
**Source**: Code review (performance)  
**Problem**: `Start-SnipManager`'s inner `Get-Filtered` function calls `LoadIdx` on every keystroke (~10–20 times/second during navigation).  
**Fix**: Load the index once when `Start-SnipManager` starts. Refresh only on actions that modify it (`n`, `e`, `d`, `g`).  
**Effort**: Low  
**Impact**: Snappier TUI on large collections; eliminates unnecessary I/O

### 8. `Get-Snip -Content` Full-Text Search Index
**Source**: Efficiency analysis  
**Problem**: `Get-Snip -Filter <term> -Content` reads every snippet file from disk for each search — O(n) file reads. With 500 snippets this is already slow; with 5000 it's unusable.  
**Fix**: On each `SaveIdx`, rebuild a lightweight in-memory full-text index (hashtable of `name → content keywords`). Persist as a sidecar `fts-cache.json` that invalidates when `index.json` changes.  
**Effort**: Medium

### 9. Staleness Detection (`Get-StaleSnip`)
**Source**: Feature research  
**Complexity**: Low  
**Description**: New function `Get-StaleSnip -DaysUnused 90` that filters snippets whose `lastRun` timestamp (already tracked in the index) is older than the threshold. Helps teams prune dead snippets.

### 10. VS Code Snippets Sync (`Export-VSCodeSnips`)
**Source**: Feature research  
**Complexity**: Low  
**Description**: Export PSSnips collection to VS Code's `~/.vscode/snippets/<lang>.json` format, making snippets available in VS Code intellisense. Two-way sync with change detection.

### 11. Fuzzy Finder Integration (`Invoke-FuzzySnip`)
**Source**: Feature research  
**Complexity**: Low  
**Description**: When `fzf` or `PSFzf` is installed, `Invoke-FuzzySnip` opens an fzf picker with snippet preview. Falls back gracefully if fzf is not found.

### 12. Windows Terminal Profile Integration
**Source**: Feature research  
**Complexity**: Low  
**Description**: `Add-SnipTerminalProfile` generates a Windows Terminal profile entry with a keybinding to launch the PSSnips TUI, custom color scheme, and font.

### 13. Execution Analytics (`Get-SnipStats`)
**Source**: Feature research  
**Complexity**: Low  
**Description**: Aggregate `runCount` and `lastRun` from the index and present a sorted leaderboard. Identifies most-used, least-used, and never-run snippets.

---

## 🟠 v1.2 — Integrations & Collaboration

Feature expansion building on the stable v1.1 base.

### 14. WSL2 Execution Support
**Source**: Feature research  
**Complexity**: Medium  
**Description**: Extend the Bash/shell runner in `Invoke-Snip` to detect WSL2 and route `.sh` snippets through it automatically, including WSL mount path translation.

### 15. PSRemoting Execution (`Invoke-Snip -ComputerName`)
**Source**: Feature research  
**Complexity**: Medium  
**Description**: Add `-ComputerName` and `-Credential` parameters to `Invoke-Snip` to run PS snippets on remote machines via `Invoke-Command`. Essential for sysadmin fleet automation.

### 16. Bitbucket Snippets Provider
**Source**: Feature research  
**Complexity**: Medium  
**Description**: Add `Get-BitbucketSnipList`, `Import-BitbucketSnip`, `Export-BitbucketSnip`, `Sync-BitbucketSnips` mirroring the existing GitHub Gist and GitLab implementations. Uses Bitbucket Cloud API v2.0.

### 17. SQL Snippet Runner
**Source**: Feature research  
**Complexity**: High  
**Description**: Add `.sql` language support in `Invoke-Snip` with a `-ConnectionString` parameter. Executes against SQL Server, MySQL, or PostgreSQL and formats results as a table. Integrates with `dbatools` if present.

### 18. Scheduled Snippet Execution (`New-SnipSchedule`)
**Source**: Feature research  
**Complexity**: Medium  
**Description**: Register snippet execution with Windows Task Scheduler at a given cron-style schedule. Output logged to `~/.pssnips/schedule.log`. Supports `Get-SnipSchedule` and `Remove-SnipSchedule`.

### 19. Snippet Ratings & Comments
**Source**: Feature research  
**Complexity**: Low → Medium  
**Description**: `Set-SnipRating -Name <n> -Stars 5` stores a rating in the index. `Add-SnipComment -Name <n> -Text "..."` appends a comment to a JSON sidecar file with timestamp and author. Visible in `Show-Snip -Comments`.

### 20. Snippet Templates & Generators (`New-SnipFromTemplate`)
**Source**: Feature research  
**Complexity**: Low  
**Description**: Scaffold new snippets from named templates stored in `~/.pssnips/templates/`. Templates support `{{VARIABLE}}` substitution (reuses existing Invoke-Snip variable system). Ships with built-in templates for Azure Function, Kubernetes Job, REST call.

### 21. Pre-Commit Hook Integration
**Source**: Feature research  
**Complexity**: Low  
**Description**: `Initialize-SnipPreCommitHook` installs a git pre-commit hook in the current repo that runs `Test-Snip` on all modified `.ps1` snippets before allowing commit.

### 22. Audit Logging
**Source**: Feature research + Enterprise  
**Complexity**: Low  
**Description**: Log all create/edit/execute/delete/export/sync operations to `~/.pssnips/audit.log` as NDJSON with timestamp, operation, snippet name, and user. Configurable retention. Required for SOC 2 / compliance environments.

---

## 🔵 v2.0 — Architectural Evolution

These are breaking or near-breaking changes that deliver a more extensible, scalable platform. Coordinate with a major version bump.

### 23. Module Split into Public/Private Files
**Source**: Architecture research  
**Complexity**: Medium  
**Description**: Decompose `PSSnips.psm1` (~3,600 lines) into a thin root loader that dot-sources:  
```
PSSnips/
├── PSSnips.psm1          (dot-source loader, ~30 lines)
├── Public/               (CRUD, Config, Tagging, Archive, Shared, TUI, CLI)
├── Private/              (DataAccess, Helpers, ApiClients, Validation)
└── Data/                 (Defaults, Colors, Templates)
```
Each file 200–400 lines, focused on one domain. The `.psd1` `RootModule` continues to point at `PSSnips.psm1`. No breaking changes to the public API.

### 24. Provider/Adapter Pattern for Remote Sources
**Source**: Architecture research  
**Complexity**: High  
**Description**: Replace the parallel `Get-GistList`/`Get-GitLabSnipList` etc. with an `IProvider` class hierarchy:
- `[IProvider]` base class with `ListSnippets`, `GetSnippet`, `CreateSnippet`, `UpdateSnippet`, `DeleteSnippet`
- `[GitHubProvider]`, `[GitLabProvider]`, `[BitbucketProvider]` implementations
- Unified public API: `Get-RemoteSnippet -Provider github`, `Sync-RemoteSnippet -Provider gitlab`
- Backwards-compatible CLI aliases: `snip gist list` → `snip remote list --provider github`

### 25. Repository Pattern for Data Layer
**Source**: Architecture research  
**Complexity**: High  
**Description**: Abstract all `LoadIdx`/`SaveIdx` calls behind an `[ISnipRepository]` interface:
- `[JsonSnipRepository]` — current flat-file implementation (default)
- `[SqliteSnipRepository]` — SQLite via PSSQLite, enables indexed queries and ACID transactions
- Business logic functions receive a `$Repository` parameter (defaults to the module-scope instance)
- Enables future cloud backends (Azure Blob, SharePoint) without touching business logic

### 26. Layered Configuration System
**Source**: Architecture research  
**Complexity**: Medium  
**Description**: Replace the flat `config.json` with a `[ConfigProvider]` class that resolves settings through a priority chain:
```
Command-line flags → Environment variables → Workspace config → User config → System defaults
```
- Adds `~/.pssnips-workspace/config.json` for per-project overrides (committable, no secrets)
- Full env-var support: `$env:PSSNIPS_EDITOR`, `$env:PSSNIPS_DIR`, `$env:PSSNIPS_WORKSPACE`
- `Set-SnipConfig -Scope workspace` saves to workspace config

### 27. Event/Hook System (`Register-SnipEvent`)
**Source**: Architecture research  
**Complexity**: Medium  
**Description**: Add an `[EventRegistry]` class at module scope. Public functions raise named events at lifecycle points. Users register handlers in `$PROFILE`:
```powershell
Register-SnipEvent -Event SnipExecuted -Handler { param($e)
    "$($e.Name) ran in $($e.Duration)s" | Add-Content ~/.pssnips/perf.log
}
Register-SnipEvent -Event SnipPublished -Handler { param($e)
    Invoke-RestMethod https://hooks.slack.com/... -Body ($e | ConvertTo-Json) -Method Post
}
```
Events: `SnipCreated`, `SnipEdited`, `SnipExecuted`, `SnipDeleted`, `SnipPublished`, `SnipSyncStart`, `SnipSyncEnd`.

### 28. Typed Output with `.ps1xml` Format Files
**Source**: Architecture research  
**Complexity**: Medium  
**Description**: Tag returned objects with `PSTypeNames` (`PSSnips.SnippetInfo`, `PSSnips.GistInfo`) and ship a `PSSnips.Format.ps1xml` registered in the manifest. This enables:
- `Get-Snip | Where-Object Language -eq ps1 | ForEach-Object { Show-Snip $_.Name }` (true pipeline support)
- `snip list --format json` via `-OutputFormat` parameter
- Custom `Format-Table` column layouts without code changes

### 29. SQLite Storage Backend
**Source**: Architecture research + Efficiency analysis  
**Complexity**: High  
**Description**: As part of the Repository pattern (#25), implement `[SqliteSnipRepository]` using the `PSSQLite` module. Benefits over flat JSON:
- O(log n) indexed queries vs O(n) hashtable scans
- Atomic transactions (solve race condition #1 permanently)
- Built-in full-text search (FTS5)
- Scales to 100,000+ snippets with no performance degradation
- Migration path: `ConvertTo-SqliteSnips` tool to migrate existing `index.json`

### 30. Class-Based Core Models
**Source**: Architecture research  
**Complexity**: High  
**Description**: Replace the hashtable-based snippet metadata with a `[SnippetMetadata]` class:
```powershell
class SnippetMetadata {
    [string]$Name; [string]$Language; [string[]]$Tags
    [bool]$Pinned; [int]$RunCount; [datetime]$LastRun
    [void] AddTag([string]$tag) { ... }
    [hashtable] ToHashtable() { ... }   # backwards compat serialization
}
```
Eliminates silent typo bugs (`$snippet.langauge` → `$null`), enables validation attributes, and makes the object model self-documenting.

---

## 🟣 Future / Long-Term Considerations

Features warranting design spikes before commitment.

### AI/LLM Integration
- `New-SnipFromDescription -Description "Deploy app to Azure"` via OpenAI/GitHub Copilot API
- `Get-SnipExplanation` — LLM-generated markdown doc for legacy snippets  
- `Get-SnipSuggestions` — PSScriptAnalyzer + LLM improvement hints  
- `Set-SnipAutoTag` — ML-based tag inference

### Enterprise / Security
- DPAPI-encrypted token storage (near-term complement to #2)
- SSO/OIDC authentication for shared snippet servers (Azure AD device flow)
- Centralized policy enforcement (`Set-SnipPolicy`)
- Secret scanning on snippet save (TruffleHog patterns for API keys/passwords)
- SIEM integration (stream audit log to Splunk/Sentinel)

### Collaboration Platform
- Public snippet registry/marketplace (GitHub-hosted index)
- Snippet forks with lineage tracking (`Fork-Snip`)
- Diff/merge tools (`Compare-Snip`, `Merge-Snip`)
- RBAC for shared snippet directories

### Additional Integrations
- Azure DevOps Snippets (enterprise team scoping)
- Obsidian Vault sync (knowledge workers)
- Docker sandbox execution (`Invoke-Snip -Runtime Docker`)
- VS Code extension with Copilot Chat integration

---

## Summary Timeline

| Release | Theme | Key Items |
|---|---|---|
| **v1.0.2** | Critical Patches | File locking (#1), token warning (#2), `$ErrorActionPreference` (#3) |
| **v1.1** | Performance & DX | Index cache (#5,#6,#7), FTS cache (#8), staleness (#9), VS Code sync (#10), fzf (#11), analytics (#13) |
| **v1.2** | Integrations | WSL2 (#14), PSRemoting (#15), Bitbucket (#16), SQL runner (#17), scheduling (#18), audit log (#22) |
| **v2.0** | Architecture | Module split (#23), provider model (#24), repository pattern (#25,#29), layered config (#26), event hooks (#27), typed output (#28), class models (#30) |
| **Future** | Platform | AI/LLM, enterprise security, collaboration, VS Code extension |

---

*Generated from: code-review, architecture analysis, feature research, efficiency analysis, and documentation audit — PSSnips v1.0.1*
