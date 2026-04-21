# PSSnips — Provider factory helper

function script:Get-RemoteProvider {
    [CmdletBinding()]
    [OutputType([RemoteProvider])]
    param(
        [ValidateSet('GitHub', 'GitLab', 'Bitbucket')]
        [string]$Name
    )
    $cfg = script:LoadCfg
    switch ($Name) {
        'GitHub' {
            $tok  = script:GetGitHubToken
            $user = if ($cfg.ContainsKey('GitHubUsername')) { $cfg['GitHubUsername'] } else { '' }
            return [GitHubProvider]::new($tok, $user)
        }
        'GitLab' {
            $tok   = script:GetGitLabToken
            $glUrl = if ($cfg.ContainsKey('GitLabUrl') -and $cfg['GitLabUrl']) { $cfg['GitLabUrl'] } else { 'https://gitlab.com' }
            return [GitLabProvider]::new($tok, $glUrl)
        }
        'Bitbucket' {
            # Check credentials exist before calling GetBitbucketCreds to avoid
            # showing the "credentials not set" warning during IsConfigured() probes.
            $hasUser = $env:BITBUCKET_USERNAME -or ($cfg.ContainsKey('BitbucketUsername') -and $cfg['BitbucketUsername'])
            $hasPass = $env:BITBUCKET_APP_PASSWORD -or ($cfg.ContainsKey('BitbucketAppPassword') -and $cfg['BitbucketAppPassword'])
            $cred = if ($hasUser -and $hasPass) { script:GetBitbucketCreds } else { $null }
            $ws   = if ($cfg.ContainsKey('BitbucketUsername') -and $cfg['BitbucketUsername']) { $cfg['BitbucketUsername'] } else { '' }
            return [BitbucketProvider]::new($cred, $ws)
        }
    }
}
