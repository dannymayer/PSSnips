# PSSnips — Get-SnipConfig and Set-SnipConfig: read/write module settings.
# Functions to read and write the PSSnips config.json settings file.

function Get-SnipConfig {
    <#
    .SYNOPSIS
        Shows the current PSSnips configuration settings.

    .DESCRIPTION
        Reads and displays all settings from the PSSnips config.json file located in
        the ~/.pssnips directory. Settings include the editor command, GitHub token
        and username, snippet storage path, default language, and delete confirmation
        preference. GitHub tokens are masked in the output, showing only the last
        four characters.

        Configuration is resolved in priority order (highest first):
          1. Environment variables  ($env:PSSNIPS_*)
          2. Workspace config       (.pssnips/config.json in cwd, or $env:PSSNIPS_WORKSPACE)
          3. User config            (~/.pssnips/config.json)
          4. Module defaults

    .PARAMETER ShowSources
        When specified, displays a table showing where each value was resolved from
        (Env / Workspace / User / Default) in addition to the value itself.

    .EXAMPLE
        Get-SnipConfig

        Displays the full configuration table in the terminal.

    .EXAMPLE
        Get-SnipConfig -ShowSources

        Displays the configuration with a Source column indicating which layer each
        value was resolved from.

    .EXAMPLE
        # Check which editor is configured before editing a snippet
        Get-SnipConfig
        Edit-Snip my-deploy-script

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Output is written directly to the host (formatted table).

    .NOTES
        Configuration is stored as JSON at ~/.pssnips/config.json.
        Use Set-SnipConfig to change individual settings.
    #>
    [CmdletBinding()]
    param(
        [switch]$ShowSources
    )
    script:InitEnv
    $cfg = script:LoadCfg
    Write-Host ""
    Write-Host "  PSSnips Configuration" -ForegroundColor Cyan
    Write-Host "  $('─' * 44)" -ForegroundColor DarkGray

    if ($ShowSources) {
        # Build per-key source map
        $defKeys  = @{}; $script:Defaults.GetEnumerator() | ForEach-Object { $defKeys[$_.Key] = $true }
        $userCfg  = @{}
        if (Test-Path $script:CfgFile) {
            try {
                $raw = Get-Content $script:CfgFile -Raw -Encoding UTF8 -ErrorAction Stop
                if ($raw) { ($raw | ConvertFrom-Json -AsHashtable).GetEnumerator() | ForEach-Object { $userCfg[$_.Key] = $true } }
            } catch { Write-Verbose "Get-SnipConfig ShowSources: user config read error — $($_.Exception.Message)" }
        }
        $wsCfg = @{}
        if ($script:WorkspaceCfgFile -and (Test-Path $script:WorkspaceCfgFile)) {
            try {
                $raw = Get-Content $script:WorkspaceCfgFile -Raw -Encoding UTF8 -ErrorAction Stop
                if ($raw) { ($raw | ConvertFrom-Json -AsHashtable).GetEnumerator() | ForEach-Object { $wsCfg[$_.Key] = $true } }
            } catch { Write-Verbose "Get-SnipConfig ShowSources: workspace config read error — $($_.Exception.Message)" }
        }

        Write-Host ("  {0,-22} {1,-30} {2}" -f 'Key', 'Value', 'Source') -ForegroundColor DarkGray
        Write-Host ("  {0,-22} {1,-30} {2}" -f ('─' * 22), ('─' * 30), ('─' * 10)) -ForegroundColor DarkGray
        foreach ($k in $cfg.Keys) {
            $v = $cfg[$k]
            if ($k -in 'GitHubToken','GitLabToken' -and $v) { $v = '[plain-text]' }
            if ($k -in 'GitHubTokenSecure','GitLabTokenSecure' -and $v) { $v = '[DPAPI encrypted]' }
            if ($k -eq 'BitbucketAppPassword' -and $v) { $v = '[set]' }
            if ($v -is [array]) { $v = $v -join ', ' }
            $envKey = ($script:EnvVarMap.GetEnumerator() | Where-Object { $_.Value -eq $k } | Select-Object -First 1)?.Key
            $src = if ($envKey -and [System.Environment]::GetEnvironmentVariable($envKey)) { 'Env' }
                   elseif ($wsCfg.ContainsKey($k))   { 'Workspace' }
                   elseif ($userCfg.ContainsKey($k))  { 'User' }
                   else                               { 'Default' }
            $srcColor = switch ($src) {
                'Env'       { 'Yellow' }
                'Workspace' { 'Green' }
                'User'      { 'Cyan' }
                default     { 'DarkGray' }
            }
            Write-Host ("  {0,-22}" -f $k) -ForegroundColor DarkCyan -NoNewline
            Write-Host (" {0,-30} " -f $v) -NoNewline
            Write-Host $src -ForegroundColor $srcColor
        }
    } else {
        foreach ($k in $cfg.Keys) {
            $v = $cfg[$k]
            if ($k -in 'GitHubToken','GitLabToken' -and $v) { $v = '[plain-text]' }
            if ($k -in 'GitHubTokenSecure','GitLabTokenSecure' -and $v) { $v = '[DPAPI encrypted]' }
            if ($k -eq 'BitbucketAppPassword' -and $v) { $v = '[set]' }
            if ($v -is [array]) { $v = $v -join ', ' }
            Write-Host ("  {0,-22}" -f $k) -ForegroundColor DarkCyan -NoNewline
            Write-Host " $v"
        }
    }
    Write-Host ""
}

function Set-SnipConfig {
    <#
    .SYNOPSIS
        Updates one or more PSSnips configuration settings.

    .DESCRIPTION
        Loads the current configuration from ~/.pssnips/config.json, applies any
        provided parameter values, and saves the updated configuration back to disk.
        Only the parameters you supply are changed; unspecified settings retain their
        current values. Multiple settings can be updated in a single call.

    .PARAMETER Editor
        The command name or path of the preferred text editor (e.g., 'edit', 'nvim',
        'code'). Optional. Falls back through EditorFallbacks if the command is not
        found on PATH.

    .PARAMETER GitHubToken
        A GitHub personal access token (PAT) with the 'gist' scope. Optional.
        Required for all Gist operations. Stored in plain text unless -SecureStorage
        is also specified. Token resolution priority at runtime:
          $env:GITHUB_TOKEN  >  GitHubTokenSecure (DPAPI)  >  GitHubToken (plain-text)
        WARNING: tokens written to config.json are not encrypted by default.
        Consider using $env:GITHUB_TOKEN for improved security.

    .PARAMETER GitLabToken
        A GitLab personal access token with 'api' scope. Optional.
        Required for all GitLab Snippet operations. Stored in plain text unless
        -SecureStorage is also specified. Token resolution priority at runtime:
          $env:GITLAB_TOKEN  >  GitLabTokenSecure (DPAPI)  >  GitLabToken (plain-text)
        WARNING: tokens written to config.json are not encrypted by default.
        Consider using $env:GITLAB_TOKEN for improved security.

    .PARAMETER BitbucketUsername
        Your Bitbucket username. Optional. Used together with BitbucketAppPassword for
        Basic Auth when calling the Bitbucket Snippets API.
        Falls back to $env:BITBUCKET_USERNAME at runtime.

    .PARAMETER BitbucketAppPassword
        A Bitbucket app password with Snippets read/write scope. Optional.
        Required for all Bitbucket Snippet operations. Falls back to
        $env:BITBUCKET_APP_PASSWORD at runtime.
        WARNING: stored in plain text in config.json; prefer the environment variable.

    .PARAMETER SecureStorage
        When specified, tokens are encrypted with Windows DPAPI before being written
        to config.json (stored under GitHubTokenSecure / GitLabTokenSecure). DPAPI
        encryption is scoped to the current machine and user account — the encrypted
        value cannot be decrypted on a different machine or by a different user.
        If DPAPI is unavailable, falls back to plain-text storage with a warning.

    .PARAMETER GitHubUsername
        Your GitHub username. Optional. Used to list your own Gists when calling
        Get-GistList without specifying -Username.

    .PARAMETER SnippetsDir
        Absolute path to the directory where snippet files are stored. Optional.
        Defaults to ~/.pssnips/snippets. The directory is created if it does not exist.

    .PARAMETER DefaultLanguage
        The file extension (without dot) used when creating a new snippet without an
        explicit -Language parameter (e.g., 'ps1', 'py', 'js'). Optional.

    .PARAMETER ConfirmDelete
        When $true (the default), Remove-Snip prompts for confirmation before
        deleting. Set to $false to suppress the confirmation prompt globally. Optional.

    .PARAMETER Scope
        Determines which config file is written. Accepted values:
          User       (default) — saves to ~/.pssnips/config.json. Applies to all
                     sessions for the current user.
          Workspace  — saves to .pssnips/config.json in the current directory (or the
                     path set in $env:PSSNIPS_WORKSPACE). Workspace settings are
                     project-specific and can be committed to source control.
                     NEVER store secrets (tokens, passwords) in workspace config.

    .EXAMPLE
        Set-SnipConfig -Editor nvim

        Switches the default editor to Neovim.

    .EXAMPLE
        Set-SnipConfig -GitHubToken 'ghp_abc123' -GitHubUsername 'octocat'

        Saves GitHub credentials to enable Gist integration (plain-text, with warning).

    .EXAMPLE
        Set-SnipConfig -GitHubToken 'ghp_abc123' -SecureStorage

        Saves the token encrypted with DPAPI (machine+user scoped).

    .EXAMPLE
        Set-SnipConfig -SnippetsDir 'C:\Projects\MySnips' -Scope Workspace

        Saves a project-specific snippets directory to the workspace config so it
        only applies when working in the current directory.

    .EXAMPLE
        Set-SnipConfig -DefaultLanguage py -ConfirmDelete $false

        Sets Python as the default language and disables delete confirmation prompts.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Writes a confirmation message to the host on success.

    .NOTES
        Settings are persisted to ~/.pssnips/config.json as UTF-8 JSON.
        Use $env:GITHUB_TOKEN or $env:GITLAB_TOKEN for the most secure token handling,
        as environment variables are never written to disk.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'User explicitly opts in to DPAPI encryption; ConvertTo-SecureString required as first step.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '',
        Justification = 'BitbucketUsername + BitbucketAppPassword are config setters, not authentication parameters.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'BitbucketAppPassword is a config setter; plain string is required for CLI input.')]
    param(
        [ValidateNotNullOrEmpty()][string]$Editor,
        [ValidateNotNullOrEmpty()][string]$GitHubToken,
        [ValidateNotNullOrEmpty()][string]$GitLabToken,
        [ValidateNotNullOrEmpty()][string]$GitHubUsername,
        [ValidateNotNullOrEmpty()][string]$SnippetsDir,
        [ValidateNotNullOrEmpty()][string]$DefaultLanguage,
        [nullable[bool]]$ConfirmDelete,
        [ValidateNotNullOrEmpty()][string]$BitbucketUsername,
        [ValidateNotNullOrEmpty()][string]$BitbucketAppPassword,
        [switch]$SecureStorage,
        [ValidateSet('User','Workspace')][string]$Scope = 'User'
    )
    script:InitEnv
    $cfg = script:LoadCfg
    if ($Editor)          { $cfg['Editor']          = $Editor          }
    if ($PSBoundParameters.ContainsKey('GitHubToken')) {
        Write-Warning "GitHub tokens stored in config.json are not encrypted. Consider using `$env:GITHUB_TOKEN instead."
        if ($SecureStorage) {
            try {
                $cfg['GitHubTokenSecure'] = $GitHubToken | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                $cfg.Remove('GitHubToken')
            } catch {
                Write-Warning "DPAPI encryption failed; falling back to plain-text storage. Error: $($_.Exception.Message)"
                $cfg['GitHubToken'] = $GitHubToken
            }
        } else {
            $cfg['GitHubToken'] = $GitHubToken
        }
    }
    if ($PSBoundParameters.ContainsKey('GitLabToken')) {
        Write-Warning "GitLab tokens stored in config.json are not encrypted. Consider using `$env:GITLAB_TOKEN instead."
        if ($SecureStorage) {
            try {
                $cfg['GitLabTokenSecure'] = $GitLabToken | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString
                $cfg.Remove('GitLabToken')
            } catch {
                Write-Warning "DPAPI encryption failed; falling back to plain-text storage. Error: $($_.Exception.Message)"
                $cfg['GitLabToken'] = $GitLabToken
            }
        } else {
            $cfg['GitLabToken'] = $GitLabToken
        }
    }
    if ($GitHubUsername)       { $cfg['GitHubUsername']       = $GitHubUsername       }
    if ($SnippetsDir)          { $cfg['SnippetsDir']          = $SnippetsDir          }
    if ($DefaultLanguage)      { $cfg['DefaultLanguage']      = $DefaultLanguage      }
    if ($null -ne $ConfirmDelete) { $cfg['ConfirmDelete']     = $ConfirmDelete        }
    if ($BitbucketUsername)    { $cfg['BitbucketUsername']    = $BitbucketUsername    }
    if ($BitbucketAppPassword) { $cfg['BitbucketAppPassword'] = $BitbucketAppPassword }
    if ($PSCmdlet.ShouldProcess("$Scope config", 'Save configuration')) {
        script:SaveCfg -Cfg $cfg -Scope $Scope
        script:Out-OK "Configuration saved."
    }
}

