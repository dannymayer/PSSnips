# PSSnips Roadmap

> **Current version**: 3.0.0
> **Published**: [PowerShell Gallery](https://www.powershellgallery.com/packages/PSSnips)
> **Scope**: Organisation & sync (v2.3) → shell integration & QoL (v2.4) → future

---

## Executive Summary

PSSnips is a production-ready, Gallery-published PowerShell 7.0+ snippet manager. It features local CRUD, GitHub Gist / GitLab / Bitbucket integration, WSL2 + PSRemoting execution, versioned history, team shared storage, interactive TUI with fuzzy search, layered configuration, event hooks, typed pipeline output, ANSI syntax highlighting, integrated PSScriptAnalyzer linting, a class-based data model, and a full provider/repository architecture.

---

## ✅ Shipped

| Version | Theme | Highlights |
|---------|-------|-----------|
| v1.0.2 | Critical Patches | File locking (atomic writes + `.lock` mutex), DPAPI token storage, `$ErrorActionPreference` fix, test isolation |
| v1.1 | Performance & DX | Index/config cache, FTS sidecar cache, argument completer TTL, TUI load optimisation, staleness detection, fzf integration, VS Code sync, Windows Terminal integration, execution analytics |
| v1.1.1 | Patch | Backspace navigation fix, missing v1.1 items |
| v1.2 | Integrations | WSL2 + bash execution, PSRemoting (`-ComputerName`), Bitbucket provider, SQL runner, Task Scheduler integration, snippet ratings & comments, `New-SnipFromTemplate`, pre-commit hook, audit logging |
| v1.2.2 | Patch | CBH metadata sync (`Sync-SnipMetadata`), TUI backspace fix |
| v2.0 | Architecture | Typed output (`PSSnips.SnippetInfo` + `.ps1xml`), 4-layer config system (`$env:` → workspace → user → defaults), event hooks (`Register-SnipEvent` / `Unregister-SnipEvent`), TUI overdraw fix |
| v2.1 | Template & Execution | `{{VAR:default}}` inline defaults, `$env:` auto-injection for templates, `Invoke-Snip -WhatIf` dry-run, author/creator metadata (`createdBy` / `updatedBy`, `Get-Snip -Author`) |
| v2.2 | Syntax & Linting | `Show-Snip -Highlighted` (PS tokenizer, zero deps), `Show-Snip -Format Auto\|Bat\|Plain` (`bat` integration), `Invoke-SnipLint` (PSSA table), `Test-SnipLint` (CI boolean) |
| v3.0 | Architecture | Module split into `Private/`+`Public/` (26 files), `[SnippetMetadata]` class model, `[JsonSnipRepository]` repository pattern, `[GitHubProvider]`/`[GitLabProvider]`/`[BitbucketProvider]` provider adapters, unified `Get-RemoteSnip`/`Sync-RemoteSnip` |

---

## 🟡 v2.3 — Organisation & Sync *(next)*

Structural organisation and multi-machine workflow.

### 1. Hierarchical Namespace Prefix (`ns/name` path-style)

**Problem**: Tags are flat strings. Large collections are hard to navigate without folder-like hierarchy.
**Fix**: Derive `Namespace` from snippet name at `/` separator (e.g. `azure/deploy`, `devops/ci/lint`). No schema change — purely derived from name. Add `Get-Snip -Namespace <prefix>` filter, TUI grouping headers, and a namespace argument completer.
**Effort**: Medium

### 2. Git Repo Sync (`Sync-SnipRepo`)

**Problem**: No native git-backed sync for a remote repository of snippets.
**Fix**: New `Sync-SnipRepo` function with `-Remote <url>`, `-Pull`, `-Push`, `-Status` modes. Config keys `SnipRepoUrl` + `SnipRepoDir`. Requires `git` in `PATH`; graceful error otherwise.
**Effort**: High

### 3. Snippet Diff Before Import (`Compare-SnipCollection`)

**Problem**: `Import-SnipCollection` blindly overwrites — no preview of incoming changes.
**Fix**: New `Compare-SnipCollection -Path <zip>` that unpacks to temp and diffs vs local. Preview table: Added / Modified / Unchanged / Conflicts. `-PassThru` returns structured objects for scripting.
**Effort**: Medium

### 4. Centralized Shared Audit Log

**Problem**: Per-user `audit.log` only. Shared-storage modifications have no cross-user attribution.
**Fix**: Append to `<SharedSnippetsDir>/shared-audit.json` on `Publish-Snip` and `Sync-SharedSnips`. Fields: `timestamp`, `operation`, `snippetName`, `user` (`$env:USERNAME`), `machine` (`$env:COMPUTERNAME`). `Get-SnipAuditLog -Shared` reads it.
**Effort**: Low

---

## 🟠 v2.4 — Shell Integration & QoL *(after v2.3)*

Deep shell integration and security polish.

### 5. PSReadLine Inline Hotkey (`Set-SnipReadLineKey`)

**Problem**: No keyboard shortcut to invoke the snippet picker from any PowerShell prompt.
**Fix**: New `Set-SnipReadLineKey` that calls `Set-PSReadLineKeyHandler` (default `Ctrl+Alt+S`). Bound action invokes `Invoke-FuzzySnip -PassThru` and inserts the selected snippet content at the cursor position in the readline buffer. Falls back to numbered menu if `fzf` is unavailable. `Install-PSSnips` gains `-IncludeReadLineKey` switch.
**Effort**: Medium

### 6. Token Redaction in Exports

**Problem**: `Export-SnipCollection -IncludeConfig` includes plain-text tokens in the ZIP.
**Fix**: Redact all token/password fields before writing config to the archive. Emit `Write-Warning` explaining the redaction. Document: use environment variables for credentials.
**Effort**: Low

### 7. Conditional Platform Variants

**Problem**: No mechanism to select snippets by OS/platform at execution time.
**Fix**: Add `platforms` metadata field (`string[]`: `windows`, `linux`, `macos`). `Invoke-Snip` checks `$IsWindows`/`$IsLinux`/`$IsMacOS` and warns/skips on mismatch. `-Force` overrides. `New-Snip -Platforms`, `Get-Snip -Platform` filter.
**Effort**: Medium

---

## 🟣 Future / Long-Term Considerations

Features warranting design spikes before commitment.

### SQLite Storage Backend
As part of the Repository pattern, implement a `[SqliteSnipRepository]` using `PSSQLite`. Benefits: O(log n) indexed queries, ACID transactions, FTS5, scales to 100k+ snippets. Migration path: `ConvertTo-SqliteSnips`.

### AI/LLM Integration
- `New-SnipFromDescription -Description "Deploy app to Azure"` via OpenAI/GitHub Copilot API
- `Get-SnipExplanation` — LLM-generated markdown documentation for legacy snippets
- `Get-SnipSuggestions` — PSScriptAnalyzer + LLM improvement hints
- `Set-SnipAutoTag` — ML-based tag inference

### Enterprise / Security
- SSO/OIDC authentication for shared snippet servers (Azure AD device flow)
- Centralized policy enforcement (`Set-SnipPolicy`)
- Secret scanning on snippet save (TruffleHog patterns for API keys/passwords)
- SIEM integration (stream audit log to Splunk/Sentinel)

### Collaboration Platform
- Public snippet registry/marketplace (GitHub-hosted index)
- Snippet forks with lineage tracking (`Fork-Snip`)
- Diff/merge tools (`Merge-Snip`)
- RBAC for shared snippet directories

### Additional Integrations
- Azure DevOps Snippets (enterprise team scoping)
- Obsidian Vault sync (knowledge workers)
- Docker sandbox execution (`Invoke-Snip -Runtime Docker`)
- VS Code extension with Copilot Chat integration

---

## Summary Timeline

| Release | Theme | Key Items |
|---------|-------|-----------|
| **v2.3** | Organisation & Sync *(next)* | Namespace prefix (#1), git repo sync (#2), diff before import (#3), shared audit log (#4) |
| **v2.4** | Shell Integration & QoL | PSReadLine hotkey (#5), token redaction (#6), platform variants (#7) |
| **Future** | Platform | SQLite backend, AI/LLM, enterprise security, collaboration, VS Code extension |

---

*Last updated: 2026-04-30 — PSSnips v3.0.0*


---

## Executive Summary

PSSnips is a production-ready, Gallery-published PowerShell 7.0+ snippet manager. It features local CRUD, GitHub Gist / GitLab / Bitbucket integration, WSL2 + PSRemoting execution, versioned history, team shared storage, interactive TUI with fuzzy search, layered configuration, event hooks, typed pipeline output, ANSI syntax highlighting, and integrated PSScriptAnalyzer linting. The roadmap below covers only **unshipped work**, now prioritised with architectural foundations first.

---

## ✅ Shipped

| Version | Theme | Highlights |
|---------|-------|-----------|
| v1.0.2 | Critical Patches | File locking (atomic writes + `.lock` mutex), DPAPI token storage, `$ErrorActionPreference` fix, test isolation |
| v1.1 | Performance & DX | Index/config cache, FTS sidecar cache, argument completer TTL, TUI load optimisation, staleness detection, fzf integration, VS Code sync, Windows Terminal integration, execution analytics |
| v1.1.1 | Patch | Backspace navigation fix, missing v1.1 items |
| v1.2 | Integrations | WSL2 + bash execution, PSRemoting (`-ComputerName`), Bitbucket provider, SQL runner, Task Scheduler integration, snippet ratings & comments, `New-SnipFromTemplate`, pre-commit hook, audit logging |
| v1.2.2 | Patch | CBH metadata sync (`Sync-SnipMetadata`), TUI backspace fix |
| v2.0 | Architecture | Typed output (`PSSnips.SnippetInfo` + `.ps1xml`), 4-layer config system (`$env:` → workspace → user → defaults), event hooks (`Register-SnipEvent` / `Unregister-SnipEvent`), TUI overdraw fix |
| v2.1 | Template & Execution | `{{VAR:default}}` inline defaults, `$env:` auto-injection for templates, `Invoke-Snip -WhatIf` dry-run, author/creator metadata (`createdBy` / `updatedBy`, `Get-Snip -Author`) |
| v2.2 | Syntax & Linting | `Show-Snip -Highlighted` (PS tokenizer, zero deps), `Show-Snip -Format Auto\|Bat\|Plain` (`bat` integration), `Invoke-SnipLint` (PSSA table), `Test-SnipLint` (CI boolean) |

---

## 🔵 v3.0 — Architectural Evolution *(next)*

Structural refactoring to make the codebase scalable, extensible, and maintainable. Implemented before v2.3/v2.4 to provide the foundations those features build on.

**Build order** (each depends on the previous):

### 1. Module Split into Public/Private Files *(first — enables parallel work)*

**Problem**: `PSSnips.psm1` exceeds 7,000 lines, making navigation, review, and contribution increasingly difficult.
**Fix**: Decompose into a thin dot-source loader with domain-scoped files:
```
PSSnips/
├── PSSnips.psm1          (dot-source loader, ~30 lines)
├── Public/               (Config, CRUD, Tags, Execution, GitHub, GitLab,
│                          Bitbucket, Shared, Archive, History, Analytics,
│                          Lint, Ratings, Templates, Scheduling, Events,
│                          Fuzzy, Integration, TUI, CLI)
└── Private/              (DataAccess, Helpers, ApiClients, FTS, Validation)
```
No breaking changes to the public API. CI updated to analyse all `.ps1`/`.psm1` files.
**Effort**: Medium

### 2. Class-Based Core Models *(second — typed foundation)*

**Problem**: Hashtable-based snippet metadata allows silent typo bugs (`$snippet.langauge` → `$null`) and has no validation or encapsulation.
**Fix**: Replace with a `[SnippetMetadata]` PowerShell class:
```powershell
class SnippetMetadata {
    [string]$Name; [string]$Language; [string[]]$Tags
    [bool]$Pinned; [int]$RunCount; [datetime]$LastRun
    [string]$Description; [string]$GistId; [string]$Author
    [string[]]$Platforms; [string]$ContentHash
    [void]   AddTag([string]$tag)      { ... }
    [void]   RemoveTag([string]$tag)   { ... }
    [hashtable] ToHashtable()          { ... }   # backwards-compat serialisation
}
```
Eliminates silent typo bugs, enables validation attributes, makes the object model self-documenting.
**Effort**: High

### 3. Repository Pattern for Data Layer *(third — data abstraction)*

**Problem**: All data access is tightly coupled to flat JSON files with no abstraction boundary.
**Fix**: Abstract `LoadIdx`/`SaveIdx` behind a `[JsonSnipRepository]` class implementing a consistent interface. Module-scope `$script:Repository` holds the active instance. Future backends (SQLite, Azure Blob) swap in without touching business logic.
**Effort**: High

### 4. Provider/Adapter Pattern for Remote Sources *(fourth — remote abstraction)*

**Problem**: GitHub Gist, GitLab, and Bitbucket are implemented as three independent parallel function sets with significant duplicated logic.
**Fix**: Introduce a class hierarchy (`[GitHubProvider]`, `[GitLabProvider]`, `[BitbucketProvider]`) behind a unified public API:
```powershell
Get-RemoteSnippet   -Provider github
Sync-RemoteSnippet  -Provider gitlab
```
Backwards-compatible aliases keep existing function names working.
**Effort**: High

---

## 🟡 v2.3 — Organisation & Sync *(after v3.0)*

### 5. Hierarchical Namespace Prefix (`ns/name` path-style)

**Problem**: Tags are flat strings. Large collections are hard to navigate without folder-like hierarchy.
**Fix**: Derive `Namespace` from snippet name at `/` separator (e.g. `azure/deploy`, `devops/ci/lint`). No schema change — purely derived from name. Add `Get-Snip -Namespace <prefix>` filter, TUI grouping headers, and a namespace argument completer.
**Effort**: Medium

### 6. Git Repo Sync (`Sync-SnipRepo`)

**Problem**: No native git-backed sync for a remote repository of snippets.
**Fix**: New `Sync-SnipRepo` function with `-Remote <url>`, `-Pull`, `-Push`, `-Status` modes. Config keys `SnipRepoUrl` + `SnipRepoDir`. Requires `git` in `PATH`; graceful error otherwise.
**Effort**: High

### 7. Snippet Diff Before Import (`Compare-SnipCollection`)

**Problem**: `Import-SnipCollection` blindly overwrites — no preview of incoming changes.
**Fix**: New `Compare-SnipCollection -Path <zip>` that unpacks to temp and diffs vs local. Preview table: Added / Modified / Unchanged / Conflicts. `-PassThru` returns structured objects for scripting.
**Effort**: Medium

### 8. Centralized Shared Audit Log

**Problem**: Per-user `audit.log` only. Shared-storage modifications have no cross-user attribution.
**Fix**: Append to `<SharedSnippetsDir>/shared-audit.json` on `Publish-Snip` and `Sync-SharedSnips`. Fields: `timestamp`, `operation`, `snippetName`, `user` (`$env:USERNAME`), `machine` (`$env:COMPUTERNAME`). `Get-SnipAuditLog -Shared` reads it.
**Effort**: Low

---

## 🟠 v2.4 — Shell Integration & QoL *(after v2.3)*

### 9. PSReadLine Inline Hotkey (`Set-SnipReadLineKey`)

**Problem**: No keyboard shortcut to invoke the snippet picker from any PowerShell prompt.
**Fix**: New `Set-SnipReadLineKey` that calls `Set-PSReadLineKeyHandler` (default `Ctrl+Alt+S`). Bound action invokes `Invoke-FuzzySnip -PassThru` and inserts the selected snippet content at the cursor position in the readline buffer. Falls back to numbered menu if `fzf` is unavailable. `Install-PSSnips` gains `-IncludeReadLineKey` switch.
**Effort**: Medium

### 10. Token Redaction in Exports

**Problem**: `Export-SnipCollection -IncludeConfig` includes plain-text tokens in the ZIP.
**Fix**: Redact all token/password fields before writing config to the archive. Emit `Write-Warning` explaining the redaction. Document: use environment variables for credentials.
**Effort**: Low

### 11. Conditional Platform Variants

**Problem**: No mechanism to select snippets by OS/platform at execution time.
**Fix**: Add `platforms` metadata field (`string[]`: `windows`, `linux`, `macos`). `Invoke-Snip` checks `$IsWindows`/`$IsLinux`/`$IsMacOS` and warns/skips on mismatch. `-Force` overrides. `New-Snip -Platforms`, `Get-Snip -Platform` filter.
**Effort**: Medium

---

## 🟣 Future / Long-Term Considerations

Features warranting design spikes before commitment.

### SQLite Storage Backend
As part of the Repository pattern (#3), implement a `[SqliteSnipRepository]` using `PSSQLite`. Benefits: O(log n) indexed queries, ACID transactions, FTS5, scales to 100k+ snippets. Migration path: `ConvertTo-SqliteSnips`.

### AI/LLM Integration
- `New-SnipFromDescription -Description "Deploy app to Azure"` via OpenAI/GitHub Copilot API
- `Get-SnipExplanation` — LLM-generated markdown documentation for legacy snippets
- `Get-SnipSuggestions` — PSScriptAnalyzer + LLM improvement hints
- `Set-SnipAutoTag` — ML-based tag inference

### Enterprise / Security
- SSO/OIDC authentication for shared snippet servers (Azure AD device flow)
- Centralized policy enforcement (`Set-SnipPolicy`)
- Secret scanning on snippet save (TruffleHog patterns for API keys/passwords)
- SIEM integration (stream audit log to Splunk/Sentinel)

### Collaboration Platform
- Public snippet registry/marketplace (GitHub-hosted index)
- Snippet forks with lineage tracking (`Fork-Snip`)
- Diff/merge tools (`Merge-Snip`)
- RBAC for shared snippet directories

### Additional Integrations
- Azure DevOps Snippets (enterprise team scoping)
- Obsidian Vault sync (knowledge workers)
- Docker sandbox execution (`Invoke-Snip -Runtime Docker`)
- VS Code extension with Copilot Chat integration

---

## Summary Timeline

| Release | Theme | Key Items |
|---------|-------|-----------|
| **v3.0** | Architecture *(next)* | Module split (#1), class models (#2), repository pattern (#3), provider pattern (#4) |
| **v2.3** | Organisation & Sync | Namespace prefix (#5), git repo sync (#6), diff before import (#7), shared audit log (#8) |
| **v2.4** | Shell Integration & QoL | PSReadLine hotkey (#9), token redaction (#10), platform variants (#11) |
| **Future** | Platform | SQLite backend, AI/LLM, enterprise security, collaboration, VS Code extension |

---

*Last updated: 2026-04-21 — PSSnips v2.2.0*

---

## ✅ Shipped

| Version | Theme | Highlights |
|---------|-------|-----------|
| v1.0.2 | Critical Patches | File locking (atomic writes + `.lock` mutex), DPAPI token storage, `$ErrorActionPreference` fix, test isolation |
| v1.1 | Performance & DX | Index/config cache, FTS sidecar cache, argument completer TTL, TUI load optimisation, staleness detection, fzf integration, VS Code sync, Windows Terminal integration, execution analytics |
| v1.1.1 | Patch | Backspace navigation fix, missing v1.1 items |
| v1.2 | Integrations | WSL2 + bash execution, PSRemoting (`-ComputerName`), Bitbucket provider, SQL runner, Task Scheduler integration, snippet ratings & comments, `New-SnipFromTemplate`, pre-commit hook, audit logging |
| v1.2.2 | Patch | CBH metadata sync (`Sync-SnipMetadata`), TUI backspace fix |
| v2.0 | Architecture | Typed output (`PSSnips.SnippetInfo` + `.ps1xml`), 4-layer config system (`$env:` → workspace → user → defaults), event hooks (`Register-SnipEvent` / `Unregister-SnipEvent`), TUI overdraw fix |
| v2.1 | Template & Execution | `{{VAR:default}}` inline defaults, `$env:` auto-injection for templates, `Invoke-Snip -WhatIf` dry-run, author/creator metadata (`createdBy` / `updatedBy`, `Get-Snip -Author`) |
| v2.2 | Syntax & Linting | `Show-Snip -Highlighted` (PS tokenizer, zero deps), `Show-Snip -Format Auto\|Bat\|Plain` (`bat` integration), `Invoke-SnipLint` (PSSA table), `Test-SnipLint` (CI boolean) |

---

## 🟡 v2.3 — Organisation & Sync

Structural organisation and multi-machine workflow gaps.

### 1. Hierarchical Namespace Prefix (`ns/name` path-style)

**Problem**: Tags are flat strings. Large collections are hard to navigate without folder-like hierarchy.
**Fix**: Derive `Namespace` from snippet name at `/` separator (e.g. `azure/deploy`, `devops/ci/lint`). No schema change — purely derived from name. Add `Get-Snip -Namespace <prefix>` filter, TUI grouping headers, and a namespace argument completer.
**Effort**: Medium

### 2. Git Repo Sync (`Sync-SnipRepo`)

**Problem**: No native git-backed sync for a remote repository of snippets.
**Fix**: New `Sync-SnipRepo` function with `-Remote <url>`, `-Pull`, `-Push`, `-Status` modes. Config keys `SnipRepoUrl` + `SnipRepoDir`. Requires `git` in `PATH`; graceful error otherwise.
**Effort**: High

### 3. Snippet Diff Before Import (`Compare-SnipCollection`)

**Problem**: `Import-SnipCollection` blindly overwrites — no preview of incoming changes.
**Fix**: New `Compare-SnipCollection -Path <zip>` that unpacks to temp and diffs vs local. Preview table: Added / Modified / Unchanged / Conflicts. `-PassThru` returns structured objects for scripting.
**Effort**: Medium

### 4. Centralized Shared Audit Log

**Problem**: Per-user `audit.log` only. Shared-storage modifications have no cross-user attribution.
**Fix**: Append to `<SharedSnippetsDir>/shared-audit.json` on `Publish-Snip` and `Sync-SharedSnips`. Fields: `timestamp`, `operation`, `snippetName`, `user` (`$env:USERNAME`), `machine` (`$env:COMPUTERNAME`). `Get-SnipAuditLog -Shared` reads it.
**Effort**: Low

---

## 🟠 v2.4 — Shell Integration & QoL

Deep shell integration and security polish.

### 5. PSReadLine Inline Hotkey (`Set-SnipReadLineKey`)

**Problem**: No keyboard shortcut to invoke the snippet picker from any PowerShell prompt.
**Fix**: New `Set-SnipReadLineKey` that calls `Set-PSReadLineKeyHandler` (default `Ctrl+Alt+S`). Bound action invokes `Invoke-FuzzySnip -PassThru` and inserts the selected snippet content at the cursor position in the readline buffer. Falls back to numbered menu if `fzf` is unavailable. `Install-PSSnips` gains `-IncludeReadLineKey` switch.
**Effort**: Medium

### 6. Token Redaction in Exports

**Problem**: `Export-SnipCollection -IncludeConfig` includes plain-text tokens in the ZIP.
**Fix**: Redact all token/password fields before writing config to the archive. Emit `Write-Warning` explaining the redaction. Document: use environment variables for credentials.
**Effort**: Low

### 7. Conditional Platform Variants

**Problem**: No mechanism to select snippets by OS/platform at execution time.
**Fix**: Add `platforms` metadata field (`string[]`: `windows`, `linux`, `macos`). `Invoke-Snip` checks `$IsWindows`/`$IsLinux`/`$IsMacOS` and warns/skips on mismatch. `-Force` overrides. `New-Snip -Platforms`, `Get-Snip -Platform` filter.
**Effort**: Medium

---

## 🔵 v3.0 — Architectural Evolution

Near-breaking changes delivering a more extensible, scalable platform. Requires major version bump.

### 8. Module Split into Public/Private Files

**Problem**: `PSSnips.psm1` exceeds 7,000 lines, making navigation and contribution difficult.
**Fix**: Decompose into a thin dot-source loader with domain files:
```
PSSnips/
├── PSSnips.psm1          (loader, ~30 lines)
├── Public/               (Config, CRUD, Tags, Execution, GitHub, GitLab,
│                          Bitbucket, Shared, Archive, History, Analytics,
│                          Lint, Ratings, Templates, Scheduling, Events,
│                          Fuzzy, Integration, TUI, CLI)
└── Private/              (DataAccess, Helpers, ApiClients, FTS, Validation)
```
No breaking changes to the public API. CI updated to analyse all `.ps1`/`.psm1` files.
**Effort**: High — deferred until after v2.4 to avoid merge conflicts during active feature work.

### 9. Provider/Adapter Pattern for Remote Sources

**Problem**: GitHub Gist, GitLab, and Bitbucket are implemented as parallel independent function sets with duplicated logic.
**Fix**: Introduce an `[IProvider]` class hierarchy (`GitHubProvider`, `GitLabProvider`, `BitbucketProvider`) behind a unified public API: `Get-RemoteSnippet -Provider github`, `Sync-RemoteSnippet -Provider gitlab`.
**Effort**: High

### 10. Repository Pattern for Data Layer

**Problem**: All data access is tightly coupled to flat JSON files.
**Fix**: Abstract `LoadIdx`/`SaveIdx` behind `[ISnipRepository]`. Default: `[JsonSnipRepository]`. Optional: `[SqliteSnipRepository]` via `PSSQLite` (ACID transactions, FTS5, scales to 100k+ snippets). Migration path: `ConvertTo-SqliteSnips`.
**Effort**: High

### 11. Class-Based Core Models

**Problem**: Hashtable-based metadata allows silent typo bugs (`$snippet.langauge` → `$null`).
**Fix**: Replace with a `[SnippetMetadata]` class with typed properties, validation attributes, and a `ToHashtable()` method for backwards-compatible serialisation.
**Effort**: High

---

## 🟣 Future / Long-Term Considerations

Features warranting design spikes before commitment.

### AI/LLM Integration
- `New-SnipFromDescription -Description "Deploy app to Azure"` via OpenAI/GitHub Copilot API
- `Get-SnipExplanation` — LLM-generated markdown documentation for legacy snippets
- `Get-SnipSuggestions` — PSScriptAnalyzer + LLM improvement hints
- `Set-SnipAutoTag` — ML-based tag inference

### Enterprise / Security
- SSO/OIDC authentication for shared snippet servers (Azure AD device flow)
- Centralized policy enforcement (`Set-SnipPolicy`)
- Secret scanning on snippet save (TruffleHog patterns for API keys/passwords)
- SIEM integration (stream audit log to Splunk/Sentinel)

### Collaboration Platform
- Public snippet registry/marketplace (GitHub-hosted index)
- Snippet forks with lineage tracking (`Fork-Snip`)
- Diff/merge tools (`Merge-Snip`)
- RBAC for shared snippet directories

### Additional Integrations
- Azure DevOps Snippets (enterprise team scoping)
- Obsidian Vault sync (knowledge workers)
- Docker sandbox execution (`Invoke-Snip -Runtime Docker`)
- VS Code extension with Copilot Chat integration

---

## Summary Timeline

| Release | Theme | Key Items |
|---------|-------|-----------|
| **v2.3** | Organisation & Sync | Namespace prefix (#1), git repo sync (#2), diff before import (#3), shared audit log (#4) |
| **v2.4** | Shell Integration & QoL | PSReadLine hotkey (#5), token redaction (#6), platform variants (#7) |
| **v3.0** | Architecture | Module split (#8), provider model (#9), repository pattern (#10), class models (#11) |
| **Future** | Platform | AI/LLM, enterprise security, collaboration, VS Code extension |

---

*Last updated: 2026-04-21 — PSSnips v2.2.0*
