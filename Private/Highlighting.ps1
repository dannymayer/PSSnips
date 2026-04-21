# PSSnips — Syntax highlighting helpers (ANSI tokenizer and bat).
function script:ConvertTo-HighlightedPS {
    <#
    .SYNOPSIS
        Applies ANSI syntax highlighting to a PowerShell code string using the built-in tokenizer.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Code
    )
    if ([string]::IsNullOrEmpty($Code)) { return $Code }

    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseInput($Code, [ref]$tokens, [ref]$errors)

    $esc   = [char]27
    $reset = "${esc}[0m"

    $hasPSStyle = $null -ne (Get-Variable -Name PSStyle -ErrorAction SilentlyContinue)

    $colorComment  = if ($hasPSStyle) { $PSStyle.Foreground.Green } else { "${esc}[32m" }
    $colorString   = "${esc}[33m"
    $colorVariable = "${esc}[35m"
    $colorKeyword  = "${esc}[94m"
    $colorNumber   = "${esc}[36m"
    $colorOperator = "${esc}[37m"
    $colorType     = "${esc}[33m"

    $result = [System.Text.StringBuilder]::new($Code.Length * 2)
    $pos    = 0

    foreach ($token in ($tokens | Sort-Object { $_.Extent.StartOffset })) {
        $start = $token.Extent.StartOffset
        $end   = $token.Extent.EndOffset

        if ($start -gt $pos) {
            $null = $result.Append($Code.Substring($pos, $start - $pos))
        }

        $tkKind  = $token.Kind
        $tkFlags = $token.TokenFlags

        $color = if ($tkKind -eq [System.Management.Automation.Language.TokenKind]::Comment) {
            $colorComment
        } elseif ($tkKind -eq [System.Management.Automation.Language.TokenKind]::StringLiteral -or
                  $tkKind -eq [System.Management.Automation.Language.TokenKind]::StringExpandable -or
                  $tkKind -eq [System.Management.Automation.Language.TokenKind]::HereStringLiteral -or
                  $tkKind -eq [System.Management.Automation.Language.TokenKind]::HereStringExpandable) {
            $colorString
        } elseif ($tkKind -eq [System.Management.Automation.Language.TokenKind]::Variable) {
            $colorVariable
        } elseif ($tkKind -eq [System.Management.Automation.Language.TokenKind]::Number) {
            $colorNumber
        } elseif ($tkFlags -band [System.Management.Automation.Language.TokenFlags]::Keyword) {
            $colorKeyword
        } elseif ($tkFlags -band [System.Management.Automation.Language.TokenFlags]::TypeName) {
            $colorType
        } elseif ($tkFlags -band ([System.Management.Automation.Language.TokenFlags]::BinaryOperator -bor
                                   [System.Management.Automation.Language.TokenFlags]::UnaryOperator)) {
            $colorOperator
        } else {
            $null
        }

        if ($color) {
            $null = $result.Append($color)
            $null = $result.Append($token.Extent.Text)
            $null = $result.Append($reset)
        } else {
            $null = $result.Append($token.Extent.Text)
        }

        $pos = $end
    }

    if ($pos -lt $Code.Length) {
        $null = $result.Append($Code.Substring($pos))
    }

    return $result.ToString()
}

function script:Invoke-BatHighlight {
    <#
    .SYNOPSIS
        Pipes source code through bat for syntax highlighting.
    #>
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Code,
        [Parameter(Mandatory)]
        [string]$Extension
    )
    if ([string]::IsNullOrEmpty($Code)) { return $Code }
    if (-not (Get-Command bat -ErrorAction SilentlyContinue)) {
        script:Out-Warn 'bat is not installed or not on PATH. Falling back to plain output.'
        return $Code
    }
    try {
        $lines = $Code | bat --language $Extension --color always --paging never --plain 2>$null
        return ($lines -join "`n")
    } catch {
        Write-Verbose "Invoke-BatHighlight: bat failed — $($_.Exception.Message)"
        return $Code
    }
}

