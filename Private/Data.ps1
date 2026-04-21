# PSSnips — Module-scoped variables: paths, defaults, colour map, and templates.
# Persistent paths, default settings, display colour map, and snippet templates
# that are shared across all functions in the module.

$script:Home      = Join-Path $env:USERPROFILE '.pssnips'
$script:CfgFile   = Join-Path $script:Home 'config.json'
$script:IdxFile   = Join-Path $script:Home 'index.json'
$script:SnipDir   = Join-Path $script:Home 'snippets'

# Advisory lock timeout (ms). Callers degrade gracefully on timeout rather than throw.
$script:LockTimeoutMs = 3000

$script:Defaults = [ordered]@{
    SnippetsDir        = $script:SnipDir
    Editor             = 'edit'
    EditorFallbacks    = @('nvim','code','notepad')
    GitHubToken        = ''
    GitHubUsername     = ''
    DefaultLanguage    = 'ps1'
    ConfirmDelete      = $true
    MaxHistory         = 10
    GitLabToken        = ''
    GitLabUrl          = 'https://gitlab.com'
    SharedSnippetsDir  = ''
    BitbucketUsername  = ''
    BitbucketAppPassword = ''
}

# Environment variable → config key mapping (used by LoadCfg for layer 3 resolution)
$script:EnvVarMap = [ordered]@{
    PSSNIPS_DIR          = 'SnippetsDir'
    PSSNIPS_EDITOR       = 'Editor'
    PSSNIPS_DEFAULT_LANG = 'DefaultLanguage'
    PSSNIPS_GITHUB_TOKEN = 'GitHubToken'
    PSSNIPS_GITHUB_USER  = 'GitHubUsername'
    PSSNIPS_GITLAB_TOKEN = 'GitLabToken'
    PSSNIPS_GITLAB_URL   = 'GitLabUrl'
    PSSNIPS_SHARED_DIR   = 'SharedSnippetsDir'
    PSSNIPS_WORKSPACE    = 'WorkspaceConfigDir'
}

$script:WorkspaceCfgFile = ''   # resolved at InitEnv time

# Map extension → color for display
$script:LangColor = @{
    ps1  = 'Cyan';    psm1 = 'Cyan';   py  = 'Yellow'; js  = 'Yellow'
    ts   = 'Blue';    bat  = 'Gray';   cmd = 'Gray';   sh  = 'Green'
    rb   = 'Red';     go   = 'Cyan';   cs  = 'Magenta';sql = 'DarkCyan'
    txt  = 'White';   md   = 'White';  json= 'DarkYellow'
}

# Placeholder templates for new snippets
$script:Templates = @{
    ps1  = "<#`n.SYNOPSIS`n    {desc}`n`n.DESCRIPTION`n    `n`n.NOTES`n    Snippet: {name}`n    Tags:`n#>`n`n"
    py   = "# {name}`n# {desc}`n`n"
    js   = "// {name}`n// {desc}`n`n"
    ts   = "// {name}`n// {desc}`n`n"
    bat  = "@echo off`nREM {name}`nREM {desc}`n`n"
    sh   = "#!/usr/bin/env bash`n# {name}`n# {desc}`n`n"
    rb   = "# {name}`n# {desc}`n`n"
    go   = "package main`n`n// {name} – {desc}`nfunc main() {`n`t`n}`n"
}

# Index/config in-memory caches (dirty = $true means reload from disk is needed)
$script:IdxCache     = $null
$script:IdxDirty     = $true
$script:CfgCache     = $null
$script:CfgDirty     = $true

# Argument-completer TTL cache
$script:CompleterCache     = $null
$script:CompleterCacheTime = [datetime]::MinValue
$script:CompleterTtlSecs   = 10

# Full-text search sidecar cache (path set in InitEnv)
$script:FtsCache     = $null
$script:FtsCacheFile = ''

# Event handler registry: hashtable of event-name → hashtable of (id → scriptblock)
$script:EventRegistry = @{}

# Active repository instance (set by InitEnv)
$script:Repository = $null

