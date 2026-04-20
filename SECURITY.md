# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅ Yes     |
| < 1.0   | ❌ No      |

Only the latest patch release of the current minor version receives security fixes.

---

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report vulnerabilities privately using GitHub's built-in vulnerability reporting:

👉 **[Report a vulnerability](https://github.com/dannymayer/PSSnips/security/advisories/new)**

You will receive an acknowledgement within **48 hours** and a status update within **7 days**.
If the vulnerability is confirmed, a patch will be released as soon as possible and you will
be credited in the release notes (unless you prefer to remain anonymous).

---

## GitHub Token Storage

PSSnips stores the GitHub personal access token (PAT) in plain text inside
`~/.pssnips/config.json` when you run `snip config -Token <pat>` or
`Set-SnipConfig -GitHubToken <pat>`.

**Recommendation:** Use the `GITHUB_TOKEN` environment variable instead of storing the token
in the config file:

```powershell
$env:GITHUB_TOKEN = 'ghp_yourTokenHere'
```

PSSnips reads `$env:GITHUB_TOKEN` as a fallback when no token is present in `config.json`.
This avoids writing the credential to disk and is the preferred approach, especially on
shared machines or in CI/CD pipelines.

If you have already stored a token in `config.json`, you can clear it with:

```powershell
Set-SnipConfig -GitHubToken ''
```
