# PSSnips — Snippet template management (New-SnipFromTemplate, Get-SnipTemplate).
function New-SnipFromTemplate {
    <#
    .SYNOPSIS
        Creates a new snippet from a named template with variable substitution.

    .DESCRIPTION
        Resolves a template by name, first checking ~/.pssnips/templates/ for custom
        templates, then falling back to built-in templates. Fills {{VARIABLE}}
        placeholders from the -Variables hashtable; any remaining placeholders are
        prompted interactively. Saves the result as a new snippet via New-Snip.

        Built-in templates:
          azure-function  PowerShell Azure Function boilerplate
                          Variables: FUNCTION_NAME, HTTP_METHOD
          rest-call       Invoke-RestMethod template
                          Variables: URL, METHOD, BODY
          k8s-job         Kubernetes Job manifest (text/YAML)
                          Variables: JOB_NAME, IMAGE

        Custom templates are stored in ~/.pssnips/templates/ as plain-text files with
        {{VARIABLE}} placeholders. The file base name is the template name.

    .PARAMETER Template
        Mandatory. The name of the template to use (e.g., 'azure-function').

    .PARAMETER Name
        Mandatory. The name for the new snippet to create.

    .PARAMETER Variables
        Optional. A hashtable of placeholder values (keys are case-insensitive).
        Any placeholder not found here is prompted interactively.

    .PARAMETER Force
        Optional switch. Overwrites an existing snippet with the same name.

    .EXAMPLE
        New-SnipFromTemplate -Template azure-function -Name my-func `
            -Variables @{ FUNCTION_NAME='MyFunc'; HTTP_METHOD='GET' }

        Creates 'my-func' from the azure-function template.

    .EXAMPLE
        New-SnipFromTemplate rest-call my-api

        Creates a snippet from the rest-call template, prompting for URL, METHOD, BODY.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        None. Delegates to New-Snip which writes a confirmation message.

    .NOTES
        Placeholder syntax: {{VARIABLE_NAME}} — uppercase letters, digits, underscores.
        Custom templates override built-in templates of the same name.
        Use Get-SnipTemplate to list all available templates.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, HelpMessage='Template name')]
        [ValidateNotNullOrEmpty()]
        [string]$Template,
        [Parameter(Mandatory, Position=1, HelpMessage='New snippet name')]
        [ValidateNotNullOrEmpty()]
        [string]$Name,
        [hashtable]$Variables = @{},
        [switch]$Force
    )
    script:InitEnv

    # ── Built-in template content (single-quoted here-strings, no variable expansion) ──
    $azFuncContent = @'
using namespace System.Net

param($Request, $TriggerMetadata)

# Azure Function: {{FUNCTION_NAME}}
# HTTP Method: {{HTTP_METHOD}}

$name = $Request.Query.Name
if (-not $name) { $name = $Request.Body.Name }

if ($name) {
    $status = [HttpStatusCode]::OK
    $body   = "Hello, $name. Function {{FUNCTION_NAME}} executed successfully."
} else {
    $status = [HttpStatusCode]::BadRequest
    $body   = 'Pass a name in the query string or request body.'
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $status
    Body       = $body
})
'@

    $restContent = @'
# REST Call to {{URL}}
# Method: {{METHOD}}

$params = @{
    Uri     = '{{URL}}'
    Method  = '{{METHOD}}'
    Headers = @{ 'Content-Type' = 'application/json' }
}

$body = '{{BODY}}'
if ($body -and $body -ne '{{BODY}}') { $params['Body'] = $body }

try {
    $response = Invoke-RestMethod @params -ErrorAction Stop
    $response | ConvertTo-Json -Depth 10
} catch {
    Write-Error "Request failed: $_"
}
'@

    $k8sContent = @'
apiVersion: batch/v1
kind: Job
metadata:
  name: {{JOB_NAME}}
spec:
  template:
    spec:
      containers:
        - name: {{JOB_NAME}}
          image: {{IMAGE}}
          imagePullPolicy: IfNotPresent
      restartPolicy: Never
  backoffLimit: 4
'@

    $builtinTemplates = @{
        'azure-function' = @{ extension = 'ps1'; content = $azFuncContent  }
        'rest-call'      = @{ extension = 'ps1'; content = $restContent     }
        'k8s-job'        = @{ extension = 'txt'; content = $k8sContent      }
    }

    # ── Resolve template ──────────────────────────────────────────────────────
    $templateContent = $null
    $templateExt     = 'ps1'
    $customDir       = Join-Path $script:Home 'templates'

    if (Test-Path $customDir) {
        $customFile = @(Get-ChildItem $customDir -Filter "$Template.*" -File -ErrorAction SilentlyContinue) | Select-Object -First 1
        if ($customFile) {
            $templateContent = Get-Content $customFile.FullName -Raw -Encoding UTF8
            $templateExt     = $customFile.Extension.TrimStart('.')
        }
    }

    if (-not $templateContent) {
        if (-not $builtinTemplates.ContainsKey($Template)) {
            Write-Error "Template '$Template' not found. Use Get-SnipTemplate to list available templates." -ErrorAction Continue
            return
        }
        $tpl             = $builtinTemplates[$Template]
        $templateContent = $tpl.content
        $templateExt     = $tpl.extension
    }

    # ── Fill placeholders ─────────────────────────────────────────────────────
    $phMatches = [regex]::Matches($templateContent, '\{\{([A-Z0-9_]+)(?::([^}]*))?\}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $placeholders = @($phMatches | ForEach-Object { $_.Groups[1].Value.ToUpper() } | Select-Object -Unique)
    $phDefaults = @{}
    foreach ($m in $phMatches) {
        $phName = $m.Groups[1].Value.ToUpper()
        if ($m.Groups[2].Success -and -not $phDefaults.ContainsKey($phName)) {
            $phDefaults[$phName] = $m.Groups[2].Value
        }
    }

    $resolved = @{}
    foreach ($k in $Variables.Keys) { $resolved[$k.ToUpper()] = $Variables[$k] }
    foreach ($ph in $placeholders) {
        if (-not $resolved.ContainsKey($ph)) {
            $envVal = (Get-Item "env:$ph" -ErrorAction SilentlyContinue).Value
            if ($envVal) {
                $resolved[$ph] = $envVal
            } elseif ($phDefaults.ContainsKey($ph) -and $phDefaults[$ph] -ne '') {
                $default = $phDefaults[$ph]
                $userInput = Read-Host "  Value for {{$ph}} [$default]"
                $resolved[$ph] = if ($userInput -ne '') { $userInput } else { $default }
            } else {
                $resolved[$ph] = Read-Host "  Value for {{$ph}}"
            }
        }
    }

    $filled = $templateContent
    foreach ($ph in $placeholders) {
        $filled = $filled -replace "\{\{$ph(?::[^}]*)?\}\}", $resolved[$ph]
    }

    New-Snip -Name $Name -Language $templateExt -Content $filled -Force:$Force
}

function Get-SnipTemplate {
    <#
    .SYNOPSIS
        Lists all available snippet templates (built-in and custom).

    .DESCRIPTION
        Displays templates from two sources:
          Built-in  — three templates embedded in the module: azure-function,
                      rest-call, and k8s-job.
          Custom    — any files stored in ~/.pssnips/templates/.
        For each template, shows its name, source (builtin/custom), extension, and a
        comma-separated list of {{VARIABLE}} placeholders it contains.

    .EXAMPLE
        Get-SnipTemplate

        Lists all available templates with their placeholder variables.

    .EXAMPLE
        $templates = Get-SnipTemplate
        $templates | Where-Object Source -eq 'custom'

        Returns only custom templates for further processing.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Each object has: Name, Source, Extension, Variables.

    .NOTES
        Custom templates are stored in ~/.pssnips/templates/.
        Custom templates override built-in templates of the same name.
        Built-in templates: azure-function, rest-call, k8s-job.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()
    script:InitEnv

    $builtinDefs = @{
        'azure-function' = @{ ext = 'ps1'; vars = @('FUNCTION_NAME', 'HTTP_METHOD') }
        'rest-call'      = @{ ext = 'ps1'; vars = @('URL', 'METHOD', 'BODY') }
        'k8s-job'        = @{ ext = 'txt'; vars = @('JOB_NAME', 'IMAGE') }
    }

    $rows = [System.Collections.Generic.List[PSCustomObject]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $customDir = Join-Path $script:Home 'templates'
    if (Test-Path $customDir) {
        foreach ($f in @(Get-ChildItem $customDir -File -ErrorAction SilentlyContinue)) {
            $tName = $f.BaseName
            $seen.Add($tName) | Out-Null
            $content = try { Get-Content $f.FullName -Raw -Encoding UTF8 -ErrorAction Stop } catch { '' }
            $vars    = @([regex]::Matches($content, '\{\{([A-Z0-9_]+)\}\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
                ForEach-Object { $_.Groups[1].Value.ToUpper() } | Select-Object -Unique)
            $rows.Add([pscustomobject]@{
                Name      = $tName
                Source    = 'custom'
                Extension = $f.Extension.TrimStart('.')
                Variables = $vars -join ', '
            })
        }
    }

    foreach ($tName in ($builtinDefs.Keys | Sort-Object)) {
        if (-not $seen.Contains($tName)) {
            $def = $builtinDefs[$tName]
            $rows.Add([pscustomobject]@{
                Name      = $tName
                Source    = 'builtin'
                Extension = $def.ext
                Variables = $def.vars -join ', '
            })
        }
    }

    $result = @($rows | Sort-Object Source, Name)
    if ($result.Count -eq 0) { script:Out-Info 'No templates found.'; return @() }

    Write-Host ''
    Write-Host '  Available Templates' -ForegroundColor Cyan
    Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
    Write-Host ("  {0,-22} {1,-8} {2,-5} {3}" -f 'NAME', 'SOURCE', 'EXT', 'VARIABLES') -ForegroundColor DarkCyan
    Write-Host "  $('─' * 72)" -ForegroundColor DarkGray
    foreach ($r in $result) {
        $c = if ($r.Source -eq 'custom') { 'Yellow' } else { 'Cyan' }
        Write-Host ("  {0,-22} " -f $r.Name) -ForegroundColor $c -NoNewline
        Write-Host ("{0,-8} {1,-5} {2}" -f $r.Source, $r.Extension, $r.Variables) -ForegroundColor Gray
    }
    Write-Host ''
    return $result
}

