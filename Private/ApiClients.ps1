# PSSnips — Low-level HTTP client wrappers for GitHub and GitLab APIs.
function script:CallGitHub {
    param(
        [string]$Endpoint,
        [string]$Method = 'GET',
        [hashtable]$Body = $null
    )
    $tok = script:GetGitHubToken
    if (-not $tok) {
        throw "GitHub token not set. Run: snip config -GitHubToken <token>  (or set `$env:GITHUB_TOKEN)"
    }
    $headers = @{
        Authorization        = "Bearer $tok"
        Accept               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'         = 'PSSnips/1.0'
    }
    $p = @{ Uri = "https://api.github.com/$Endpoint"; Method = $Method; Headers = $headers }
    if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p -ErrorAction Stop
}

function script:CallGitLab {
    param(
        [string]$Endpoint,
        [string]$Method   = 'GET',
        [hashtable]$Body  = $null
    )
    $cfg   = script:LoadCfg
    $tok   = script:GetGitLabToken
    if (-not $tok) {
        throw "GitLab token not set. Run: snip config -GitLabToken <token>  (or set `$env:GITLAB_TOKEN)"
    }
    $glUrl = if ($cfg.ContainsKey('GitLabUrl') -and $cfg.GitLabUrl) { $cfg.GitLabUrl.TrimEnd('/') } else { 'https://gitlab.com' }
    $headers = @{ 'PRIVATE-TOKEN' = $tok; 'User-Agent' = 'PSSnips/1.0' }
    $p = @{ Uri = "$glUrl/api/v4/$Endpoint"; Method = $Method; Headers = $headers }
    if ($Body) { $p.Body = ($Body | ConvertTo-Json -Depth 10); $p.ContentType = 'application/json' }
    return Invoke-RestMethod @p -ErrorAction Stop
}

