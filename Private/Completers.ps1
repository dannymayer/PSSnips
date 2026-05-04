# PSSnips — Tab-completion registrations for snippet name parameters.
# Tab-completion for snippet names on all relevant commands.

$snipNameCompleter = {
    param($cmd, $param, $word)
    $null = $cmd, $param
    $now = Get-Date
    if ($null -eq $script:CompleterCache -or
        ($now - $script:CompleterCacheTime).TotalSeconds -gt $script:CompleterTtlSecs) {
        $script:CompleterCache = (script:LoadIdx).snippets.Keys | Sort-Object
        $script:CompleterCacheTime = $now
    }
    $script:CompleterCache | Where-Object { $_ -like "$word*" }
}

Register-ArgumentCompleter -CommandName 'Invoke-SnipCLI','snip','Show-Snip','Edit-Snip','Invoke-Snip','Remove-Snip','Copy-Snip','Export-Gist','Sync-Gist','Set-SnipTag','Invoke-SnipLint','Test-SnipLint' -ParameterName Name -ScriptBlock $snipNameCompleter
Register-ArgumentCompleter -CommandName 'Invoke-SnipCLI','snip' -ParameterName Arg1 -ScriptBlock $snipNameCompleter

Register-ArgumentCompleter -CommandName 'Get-Snip' -ParameterName 'Namespace' -ScriptBlock {
    param($commandName, $paramName, $wordToComplete, $commandAst, $fakeBoundParams)
    $null = $commandName, $paramName, $commandAst, $fakeBoundParams
    script:InitEnv
    $idx = script:LoadIdx
    $idx.snippets.Keys |
        Where-Object { $_ -match '/' } |
        ForEach-Object { ($_ -split '/')[0] } |
        Sort-Object -Unique |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

Register-ArgumentCompleter -CommandName 'New-Snip' -ParameterName 'Platforms' -ScriptBlock {
    param($commandName, $paramName, $wordToComplete, $commandAst, $fakeBoundParams)
    $null = $commandName, $paramName, $commandAst, $fakeBoundParams
    @('windows','linux','macos') |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

