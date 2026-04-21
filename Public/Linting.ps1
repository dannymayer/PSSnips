# PSSnips — Snippet linting via PSScriptAnalyzer (Invoke-SnipLint, Test-SnipLint).
function Invoke-SnipLint {
    <#
    .SYNOPSIS
        Runs PSScriptAnalyzer on a snippet and displays diagnostics.

    .DESCRIPTION
        Invokes PSScriptAnalyzer against the snippet file identified by Name.
        Only applicable to PowerShell snippets (.ps1, .psm1, .psd1).
        Results are displayed as a formatted table showing Line, Column, Severity,
        RuleName, and Message. Returns the diagnostic objects for pipeline use.

    .PARAMETER Name
        The snippet name to analyse.

    .PARAMETER Severity
        Filter diagnostics by severity. Defaults to Error, Warning, Information.

    .PARAMETER IncludeRule
        Pass-through to Invoke-ScriptAnalyzer. Specifies rules to include.

    .PARAMETER ExcludeRule
        Pass-through to Invoke-ScriptAnalyzer. Specifies rules to exclude.

    .EXAMPLE
        Invoke-SnipLint deploy-app

        Runs all default PSScriptAnalyzer rules against the 'deploy-app' snippet.

    .EXAMPLE
        Invoke-SnipLint deploy-app -Severity Error,Warning

        Reports only Error and Warning findings.

    .INPUTS
        None.

    .OUTPUTS
        Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord
    #>
    [CmdletBinding()]
    [OutputType('Microsoft.Windows.PowerShell.ScriptAnalyzer.Generic.DiagnosticRecord')]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Error','Warning','Information','ParseError')]
        [string[]]$Severity = @('Error','Warning','Information'),

        [Parameter()]
        [string[]]$IncludeRule = @(),

        [Parameter()]
        [string[]]$ExcludeRule = @()
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return }

    $ext = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
    if ($ext -notin @('ps1','psm1','psd1')) {
        script:Out-Warn "Lint is only available for PowerShell snippets (.ps1, .psm1, .psd1). Got .$ext."
        return
    }

    if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
        script:Out-Warn 'PSScriptAnalyzer is not installed. Install it with: Install-Module PSScriptAnalyzer'
        return
    }

    $saParams = @{ Path = $path; Severity = $Severity }
    if ($IncludeRule.Count -gt 0) { $saParams['IncludeRule'] = $IncludeRule }
    if ($ExcludeRule.Count -gt 0) { $saParams['ExcludeRule'] = $ExcludeRule }

    $results = Invoke-ScriptAnalyzer @saParams

    if (-not $results -or $results.Count -eq 0) {
        script:Out-OK "No issues found in '$Name'."
        return
    }

    script:Out-Warn ("Found {0} issue(s) in '{1}':" -f $results.Count, $Name)
    $results | Select-Object Line,Column,Severity,RuleName,Message | Format-Table -AutoSize | Out-String | Write-Host
    return $results
}

function Test-SnipLint {
    <#
    .SYNOPSIS
        Tests a snippet with PSScriptAnalyzer and returns pass/fail.

    .DESCRIPTION
        Runs PSScriptAnalyzer on the named snippet. Returns $true if no issues at
        or above the specified severity are found, $false otherwise.
        Only applicable to PowerShell snippets (.ps1, .psm1, .psd1).

    .PARAMETER Name
        The snippet name to test.

    .PARAMETER Severity
        Severity levels to treat as failures. Defaults to Error, Warning.

    .EXAMPLE
        if (-not (Test-SnipLint deploy-app)) { throw 'Snippet has PSSA violations' }

    .EXAMPLE
        Test-SnipLint deploy-app -Severity Error

        Returns $true only if no Error-severity findings exist.

    .INPUTS
        None.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Error','Warning','Information','ParseError')]
        [string[]]$Severity = @('Error','Warning')
    )
    script:InitEnv
    $path = script:FindFile -Name $Name
    if (-not $path -or -not (Test-Path $path)) { Write-Error "Snippet '$Name' not found." -ErrorAction Continue; return $false }

    $ext = [System.IO.Path]::GetExtension($path).TrimStart('.').ToLower()
    if ($ext -notin @('ps1','psm1','psd1')) {
        script:Out-Warn "Lint is only available for PowerShell snippets (.ps1, .psm1, .psd1). Got .$ext."
        return $false
    }

    if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
        script:Out-Warn 'PSScriptAnalyzer is not installed. Install it with: Install-Module PSScriptAnalyzer'
        return $false
    }

    $saParams = @{ Path = $path; Severity = $Severity }

    $results = Invoke-ScriptAnalyzer @saParams
    $passed = (-not $results -or $results.Count -eq 0)

    if ($passed) {
        script:Out-OK "Test-SnipLint '$Name': PASSED"
    } else {
        script:Out-Warn ("Test-SnipLint '$Name': {0} issue(s) found (Severity: {1})" -f $results.Count, ($Severity -join ','))
    }
    return $passed
}

