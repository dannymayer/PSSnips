# PSSnips — Shell profile integration (Install-PSSnips, Uninstall-PSSnips).

function Install-PSSnips {
    <#
    .SYNOPSIS
        Adds PSSnips to a PowerShell profile so it loads automatically.
    .DESCRIPTION
        Locates the specified PowerShell profile file, creates it if it doesn't exist,
        and appends an Import-Module line for PSSnips if not already present.
    .PARAMETER Scope
        The profile scope to modify. Default: CurrentUserCurrentHost.
        Valid values: CurrentUserCurrentHost, CurrentUserAllHosts,
                      AllUsersCurrentHost, AllUsersAllHosts.
    .PARAMETER Force
        Optional switch. Adds the import line even if PSSnips is already in the profile.
    .EXAMPLE
        Install-PSSnips
    .EXAMPLE
        Install-PSSnips -Scope CurrentUserAllHosts
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        After installation, restart PowerShell or dot-source the profile file.
        Supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('CurrentUserCurrentHost','CurrentUserAllHosts','AllUsersCurrentHost','AllUsersAllHosts')]
        [string]$Scope = 'CurrentUserCurrentHost',
        [switch]$Force,
        [switch]$IncludeReadLineKey
    )
    script:InitEnv
    $profilePath = $PROFILE.$Scope
    $importLine  = "Import-Module '$($MyInvocation.MyCommand.Module.Path)'"

    if ($PSCmdlet.ShouldProcess($profilePath, "Add PSSnips import")) {
        # Create profile if it doesn't exist
        if (-not (Test-Path $profilePath)) {
            $profileDir = Split-Path $profilePath -Parent
            if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
            Set-Content $profilePath -Value "# PowerShell Profile`n" -Encoding UTF8
        }

        # Check if already present
        $existing = Select-String -Path $profilePath -Pattern 'PSSnips' -ErrorAction SilentlyContinue
        if ($existing -and -not $Force) {
            script:Out-Info "PSSnips already in profile at $profilePath"
            return
        }

        # Append import line
        Add-Content $profilePath -Value "`n$importLine" -Encoding UTF8
        script:Out-OK "PSSnips added to profile: $profilePath"
        script:Out-Info "Restart PowerShell or run: . `"$profilePath`""

        if ($IncludeReadLineKey) {
            $keyLine = "`nSet-SnipReadLineKey  # PSSnips hotkey (Ctrl+Alt+S)"
            Add-Content $profilePath -Value $keyLine -Encoding UTF8
            script:Out-Info "PSReadLine hotkey configured. Press Ctrl+Alt+S to open snippet picker."
        }
    }
}

function Uninstall-PSSnips {
    <#
    .SYNOPSIS
        Removes PSSnips from a PowerShell profile.
    .DESCRIPTION
        Reads the specified profile file and removes any lines containing 'PSSnips',
        then writes the cleaned content back.
    .PARAMETER Scope
        The profile scope to modify. Default: CurrentUserCurrentHost.
    .EXAMPLE
        Uninstall-PSSnips
    .INPUTS
        None.
    .OUTPUTS
        None.
    .NOTES
        Supports -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('CurrentUserCurrentHost','CurrentUserAllHosts','AllUsersCurrentHost','AllUsersAllHosts')]
        [string]$Scope = 'CurrentUserCurrentHost'
    )
    $profilePath = $PROFILE.$Scope
    if (-not (Test-Path $profilePath)) {
        script:Out-Info "Profile not found: $profilePath"
        return
    }
    if ($PSCmdlet.ShouldProcess($profilePath, "Remove PSSnips import")) {
        $lines   = @(Get-Content $profilePath -Encoding UTF8)
        $cleaned = @($lines | Where-Object { $_ -notmatch 'PSSnips' })
        Set-Content $profilePath -Value $cleaned -Encoding UTF8
        script:Out-OK "PSSnips removed from profile: $profilePath"
    }
}

