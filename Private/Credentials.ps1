# PSSnips — Credential retrieval helpers (GitHub, GitLab, Bitbucket).
function script:GetGitHubToken {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    $cfg = script:LoadCfg
    if ($cfg.ContainsKey('GitHubTokenSecure') -and $cfg.GitHubTokenSecure) {
        try {
            $secure = $cfg.GitHubTokenSecure | ConvertTo-SecureString
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        } catch { Write-Verbose "GetGitHubToken: DPAPI decryption failed — $($_.Exception.Message)" }
    }
    return $cfg.GitHubToken
}

function script:GetGitLabToken {
    if ($env:GITLAB_TOKEN) { return $env:GITLAB_TOKEN }
    $cfg = script:LoadCfg
    if ($cfg.ContainsKey('GitLabTokenSecure') -and $cfg.GitLabTokenSecure) {
        try {
            $secure = $cfg.GitLabTokenSecure | ConvertTo-SecureString
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        } catch { Write-Verbose "GetGitLabToken: DPAPI decryption failed — $($_.Exception.Message)" }
    }
    return $cfg.GitLabToken
}

function script:GetBitbucketCreds {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'App password comes from env var or config; PSCredential requires SecureString.')]
    param()
    $cfg  = script:LoadCfg
    $user = if ($env:BITBUCKET_USERNAME)     { $env:BITBUCKET_USERNAME }
            elseif ($cfg.ContainsKey('BitbucketUsername')    -and $cfg.BitbucketUsername)    { $cfg.BitbucketUsername }
            else { $null }
    $pass = if ($env:BITBUCKET_APP_PASSWORD) { $env:BITBUCKET_APP_PASSWORD }
            elseif ($cfg.ContainsKey('BitbucketAppPassword') -and $cfg.BitbucketAppPassword) { $cfg.BitbucketAppPassword }
            else { $null }
    if (-not $user -or -not $pass) {
        script:Out-Warn 'Bitbucket credentials not set. Run: Set-SnipConfig -BitbucketUsername <user> -BitbucketAppPassword <app-pwd>  (or set $env:BITBUCKET_USERNAME / $env:BITBUCKET_APP_PASSWORD)'
        return $null
    }
    $securePass = ConvertTo-SecureString $pass -AsPlainText -Force
    return [PSCredential]::new($user, $securePass)
}

