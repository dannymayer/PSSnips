# PSSnips – PowerShell Snippet Manager

A terminal-first snippet manager for PowerShell 7.0+ on Windows, with GitHub Gist integration and support for Microsoft Edit, Neovim, and VS Code.

---

## Requirements

- **PowerShell 7.0+** (PowerShell Core — `pwsh.exe`)
- **Windows** (uses Windows clipboard, console APIs, and `~\.pssnips\` data path)

---

## Quick Start

```powershell
# Install from the PowerShell Gallery (recommended)
Install-Module PSSnips

snip            # launch interactive TUI
snip help       # show all commands
```

---

## Installation

### From the PowerShell Gallery (recommended)

```powershell
Install-Module PSSnips
```

### Manual install

1. Clone or copy the `PSSnips` folder anywhere you like.
2. Import the module in your PowerShell session:

```powershell
Import-Module "C:\...\PSSnips\PSSnips.psd1"
```

3. (Optional) Add to `$PROFILE` for permanent access:

```powershell
Add-Content $PROFILE "`nImport-Module PSSnips"
```

4. (Optional) Add a GitHub token to enable Gist features:

```powershell
snip config -Token ghp_yourPersonalAccessToken
snip config -Username your-github-username
```

Data is stored in `~\.pssnips\` (config, index, and snippet files).

---

## Commands

### Interactive TUI

```powershell
snip            # or: snip ui
```

| Key | Action |
|-----|--------|
| ↑ ↓ | Navigate |
| Enter / → | View snippet |
| `n` | New snippet |
| `e` | Edit in editor |
| `r` | Run snippet |
| `c` | Copy to clipboard |
| `d` | Delete |
| `g` | Export to GitHub Gist |
| `/` | Search / filter |
| `q` | Quit |

---

### Snippet Commands

```powershell
# List all snippets
snip list
snip list azure           # filter by name/description/tags

# Search
snip search deploy

# Create a new snippet (opens in editor)
snip new my-script
snip new deploy -Language ps1 -Description 'Azure deploy script'
snip new parser -Language py -Tags 'data','util'

# Add from a file
snip add loader -Path .\loader.py

# Add from clipboard
snip add my-note -Clip -Language md

# Pipe content in
Get-Content .\script.ps1 | snip add my-piped -Language ps1

# Display a snippet
snip show my-script
snip cat my-script -Raw     # raw, no header

# Edit in Microsoft Edit (or configured editor)
snip edit my-script
snip edit my-script -Editor nvim
snip edit my-script -Editor code

# Run a snippet
snip run my-script
snip run my-script -- -Verbose   # pass arguments

# Copy to clipboard
snip copy my-script

# Tag management
snip tag my-script -Tags 'devops','azure'

# Delete
snip rm my-script
snip rm my-script -Force    # skip confirmation
```

---

### GitHub Gist Commands

> Requires a GitHub Personal Access Token with `gist` scope.
> Generate one at: https://github.com/settings/tokens

```powershell
# Configure token
snip config -Token ghp_yourTokenHere
snip config -Username your-github-username

# List your gists
snip gist list
snip gist list deploy       # filter

# View a gist
snip gist show abc123def456

# Import a gist as a local snippet
snip gist import abc123def456
snip gist import abc123def456 my-local-name

# Export a snippet to GitHub as a Gist
snip gist push my-script
snip gist push my-script -Public   # public gist

# Run a gist without saving
snip gist run abc123def456

# Sync (pull latest from GitHub)
snip gist sync my-script
snip gist sync my-script -Push     # push local → GitHub
```

---

### Configuration

```powershell
# Show current config
snip config

# Set GitHub token
snip config -Token ghp_...

# Change editor
snip config -Editor nvim     # options: edit, nvim, code, notepad, vim, micro
snip config -Editor code

# Change default language for new snippets
snip config -Language py

# Change snippets directory
Set-SnipConfig -SnippetsDir 'D:\MySnippets'

# Disable delete confirmation
Set-SnipConfig -ConfirmDelete $false
```

---

## Supported Languages / Runners

| Extension | Language   | Runner    |
|-----------|------------|-----------|
| `.ps1`    | PowerShell | Built-in  |
| `.py`     | Python     | `python`  |
| `.js`     | JavaScript | `node`    |
| `.bat`    | Batch      | `cmd /c`  |
| `.cmd`    | Batch      | `cmd /c`  |
| `.sh`     | Bash/Shell | `bash` / WSL |
| `.rb`     | Ruby       | `ruby`    |
| `.go`     | Go         | `go run`  |

---

## Editor Priority

PSSnips will use the first available editor from this list:

1. **Microsoft Edit** (`edit.exe`) – built-in terminal editor (Windows 11 24H2+)
2. **Neovim** (`nvim`)
3. **VS Code** (`code`)
4. **Notepad** (`notepad`) – always available fallback

Override at any time: `snip edit mysnip -Editor code`

---

## Data Layout

```
~\.pssnips\
├── config.json        # settings
├── index.json         # snippet metadata index
└── snippets\
    ├── deploy.ps1
    ├── parse-csv.py
    └── ...
```

---

## Using as a Module in $PROFILE

```powershell
# Add to your PowerShell profile ($PROFILE):
Import-Module PSSnips -ErrorAction SilentlyContinue
```

---

## GitHub Token Permissions

When creating a token at https://github.com/settings/tokens, grant:

- `gist` – read/write access to your Gists

That's all that's needed for Gist features.
