# PSSnips Roadmap

> **Current version**: 2.2.0
> **Published**: [PowerShell Gallery](https://www.powershellgallery.com/packages/PSSnips)
> **Scope**: Remaining near-term enhancements → long-term architectural evolution

---

## Executive Summary

PSSnips is a production-ready, Gallery-published PowerShell 7.0+ snippet manager. It features local CRUD, GitHub Gist / GitLab / Bitbucket integration, WSL2 + PSRemoting execution, versioned history, team shared storage, interactive TUI with fuzzy search, layered configuration, event hooks, typed pipeline output, ANSI syntax highlighting, and integrated PSScriptAnalyzer linting. The roadmap below covers only **unshipped work**.

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
