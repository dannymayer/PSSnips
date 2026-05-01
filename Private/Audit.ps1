# PSSnips — Audit logging and shared-directory helpers.
function script:Write-AuditLog {
    param(
        [string]$Operation,
        [string]$SnippetName = '',
        [hashtable]$Extra    = @{}
    )
    try {
        $auditFile = Join-Path $script:Home 'audit.log'
        if ((Test-Path $auditFile) -and (Get-Item $auditFile -ErrorAction SilentlyContinue).Length -gt 10MB) {
            $rotated = "$auditFile.1"
            if (Test-Path $rotated) { Remove-Item $rotated -Force -ErrorAction SilentlyContinue }
            Rename-Item -Path $auditFile -NewName 'audit.log.1' -Force -ErrorAction SilentlyContinue
        }
        $entry = [ordered]@{
            timestamp   = (Get-Date -Format 'o')
            operation   = $Operation
            snippetName = $SnippetName
            user        = $env:USERNAME
        }
        foreach ($k in $Extra.Keys) { $entry[$k] = $Extra[$k] }
        $line = $entry | ConvertTo-Json -Compress
        Add-Content -Path $auditFile -Value $line -Encoding UTF8 -ErrorAction Stop
    } catch { Write-Verbose "Audit log write failed (non-fatal): $($_.Exception.Message)" }
}

function script:GetSharedDir {
    $cfg = script:LoadCfg
    $dir = if ($cfg.ContainsKey('SharedSnippetsDir')) { $cfg['SharedSnippetsDir'] } else { '' }
    if (-not $dir) { script:Out-Warn "SharedSnippetsDir is not configured. Run: Set-SnipConfig -SharedSnippetsDir <path>"; return $null }
    if (-not (Test-Path $dir)) { script:Out-Warn "SharedSnippetsDir '$dir' is not accessible."; return $null }
    return $dir
}

function script:Append-SharedAudit {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    param(
        [string]$Operation,
        [string]$SnippetName
    )
    $sharedDir = script:GetSharedDir
    if (-not $sharedDir) { return }
    $auditPath = Join-Path $sharedDir 'shared-audit.json'
    $entry = @{
        timestamp   = (Get-Date -Format 'o')
        operation   = $Operation
        snippetName = $SnippetName
        user        = "$env:USERDOMAIN\$env:USERNAME"
        machine     = $env:COMPUTERNAME
    }
    $existing = if (Test-Path $auditPath) {
        try { Get-Content $auditPath -Raw | ConvertFrom-Json -AsHashtable } catch { @() }
    } else { @() }
    $list = [System.Collections.Generic.List[object]]::new()
    if ($existing -is [array]) { foreach ($e in $existing) { $list.Add($e) } }
    elseif ($null -ne $existing) { $list.Add($existing) }
    $list.Add($entry)
    $json = $list | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($auditPath, $json, (New-Object System.Text.UTF8Encoding $true))
}

