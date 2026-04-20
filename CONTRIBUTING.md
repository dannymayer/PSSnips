# Contributing to PSSnips

Thank you for your interest in contributing! This document covers everything you need to get started.

---

## Getting Started

### Clone and import locally

```powershell
git clone https://github.com/dannymayer/PSSnips.git
cd PSSnips

# Import the module directly from the working directory
Import-Module .\PSSnips.psd1 -Force
```

After importing, all exported functions and the `snip` alias are available in your session.

---

## Running Tests

Tests live in `PSSnips.Tests.ps1`. They are being converted to [Pester](https://pester.dev) format.
Run them with:

```powershell
# Current format (custom test runner)
.\PSSnips.Tests.ps1

# Once Pester conversion is complete
Invoke-Pester .\PSSnips.Tests.ps1 -Output Detailed
```

All 73 tests must pass before a PR is merged.

---

## Running PSScriptAnalyzer

```powershell
# Install if not already present
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force

# Analyse the module
Invoke-ScriptAnalyzer -Path .\PSSnips.psm1

# Analyse the manifest too
Invoke-ScriptAnalyzer -Path .\PSSnips.psd1
```

Fix all **Error** and **Warning** severity findings before submitting a PR.
**Information** findings are advisory; address them where practical.

---

## Branch Naming

| Prefix | Purpose | Example |
|--------|---------|---------|
| `feature/*` | New functionality | `feature/gitlab-mr-support` |
| `fix/*` | Bug fixes | `fix/import-gist-encoding` |
| `docs/*` | Documentation only | `docs/contributing-guide` |
| `chore/*` | Tooling, CI, dependencies | `chore/bump-pester-version` |

Branch names must be lowercase and use hyphens (no underscores or spaces).

---

## Pull Request Guidelines

1. **One concern per PR** — keep scope small and focused.
2. **Link the issue** — reference `Closes #<issue>` in the PR description.
3. **Tests required** — every new public function needs at least one test.
4. **No breaking changes** without a prior discussion in an issue.
5. **Keep the changelog up to date** — add an entry under `[Unreleased]` in `CHANGELOG.md`.
6. **Squash trivial fixup commits** before requesting review.

---

## Code Style

- **Indentation**: 4 spaces — no tabs.
- **Naming**: Verb-Noun for all public functions (`Approved-Verb`; run `Get-Verb` for the full list).
- **No `+=` on collections** — use `[System.Collections.Generic.List[object]]` or `@()` builder patterns.
- **Error handling**: never leave catch blocks empty — at minimum `Write-Verbose` the exception message.
- **Comments**: comment *why*, not *what*. Avoid noise comments that restate the code.
- **String formatting**: prefer `-f` formatting or string interpolation over concatenation.
- **Output**: use `Write-Verbose` for diagnostic messages, `Write-Warning` for non-fatal issues,
  `Write-Error` for failures. Avoid `Write-Host` except in TUI/display functions.
- **Compatibility**: code must run on both Windows PowerShell 5.1 and PowerShell 7+.
  Test with both before submitting.

---

## Reporting Issues

Please use [GitHub Issues](https://github.com/dannymayer/PSSnips/issues) and include:
- PowerShell version (`$PSVersionTable`)
- Operating system
- Steps to reproduce
- Expected vs actual behaviour
