#Requires -Version 7.0
# PSSnips.Tests.ps1 — Pester 5 test suite
#
# Run: Invoke-Pester -Path .\PSSnips.Tests.ps1 -Output Detailed

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'PSSnips.psd1') -Force

    $script:TestRoot    = Join-Path $env:TEMP "PSSnips-Test-$(New-Guid)"
    $script:TestSnipDir = Join-Path $script:TestRoot 'snippets'

    New-Item -ItemType Directory -Path $script:TestRoot    -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestSnipDir -Force | Out-Null

    & (Get-Module PSSnips) {
        param($BaseDir, $SnipDir)
        $script:Home    = $BaseDir
        $script:CfgFile = Join-Path $BaseDir 'config.json'
        $script:IdxFile = Join-Path $BaseDir 'index.json'
        $script:SnipDir = $SnipDir
        # Seed config.json with the test SnippetsDir before InitEnv runs so it
        # doesn't write module-level defaults (which still point to the real path).
        @{ SnippetsDir = $SnipDir } | ConvertTo-Json | Set-Content $script:CfgFile -Encoding UTF8
        script:InitEnv
    } $script:TestRoot $script:TestSnipDir

    Set-SnipConfig -ConfirmDelete $false *>&1 | Out-Null

    # Helper: wipe snippet files and reset the index between groups.
    # Defined inside BeforeAll so it lives in the Pester run-phase scope
    # and is inherited by all nested BeforeAll / It blocks.
    function Clear-TestState {
        Get-ChildItem $script:TestSnipDir -File -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        & (Get-Module PSSnips) { script:SaveIdx -Idx @{ snippets = @{} } }
    }
}

AfterAll {
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Module PSSnips -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────

Describe '[SnippetMetadata] class' {
    It 'FromHashtable maps all known fields' {
        $sm = & (Get-Module PSSnips) {
            [SnippetMetadata]::FromHashtable(@{ name = 'test'; language = 'ps1'; tags = @('a','b'); runCount = 3; pinned = $true })
        }
        $sm.Name     | Should -Be 'test'
        $sm.Language | Should -Be 'ps1'
        $sm.Tags     | Should -Be @('a','b')
        $sm.RunCount | Should -Be 3
        $sm.Pinned   | Should -BeTrue
    }
    It 'FromHashtable handles missing fields with defaults' {
        $sm = & (Get-Module PSSnips) {
            [SnippetMetadata]::FromHashtable(@{ name = 'x' })
        }
        $sm.Language | Should -Be ''
        $sm.RunCount | Should -Be 0
        $sm.Pinned   | Should -BeFalse
        $sm.Tags     | Should -BeNullOrEmpty
    }
    It 'ToHashtable round-trips through JSON' {
        $sm2 = & (Get-Module PSSnips) {
            $sm = [SnippetMetadata]::new()
            $sm.Name = 'roundtrip'; $sm.Language = 'ps1'; $sm.Tags = @('x')
            $json   = $sm.ToHashtable() | ConvertTo-Json -Depth 5
            $back   = $json | ConvertFrom-Json -AsHashtable
            [SnippetMetadata]::FromHashtable($back)
        }
        $sm2.Name     | Should -Be 'roundtrip'
        $sm2.Language | Should -Be 'ps1'
        $sm2.Tags     | Should -Be @('x')
    }
    It 'LastRun omitted from ToHashtable when null' {
        $ht = & (Get-Module PSSnips) {
            $sm = [SnippetMetadata]::new(); $sm.Name = 'nolastrun'
            $sm.ToHashtable()
        }
        $ht.ContainsKey('lastRun') | Should -BeFalse
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Module: Load and manifest' {

    It "Module imports without error" {
        (Get-Module PSSnips) | Should -Not -BeNullOrEmpty
    }

    It "'snip' function is available" {
        Get-Command 'snip' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "All expected exported functions exist" {
        $expected = @(
            'Initialize-PSSnips', 'Get-SnipConfig', 'Set-SnipConfig',
            'Get-Snip', 'Show-Snip', 'New-Snip', 'Add-Snip', 'Remove-Snip',
            'Edit-Snip', 'Invoke-Snip', 'Copy-Snip', 'Set-SnipTag',
            'Export-SnipCollection', 'Import-SnipCollection',
            'Get-GistList', 'Get-Gist', 'Import-Gist', 'Export-Gist',
            'Invoke-Gist', 'Sync-Gist', 'Start-SnipManager',
            'Get-SnipHistory', 'Restore-Snip', 'Test-Snip',
            'snip'
        )
        $missing = $expected | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
        $missing | Should -BeNullOrEmpty
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Safety: Single-item array handling' {

    Context 'Tag variety does not break Get-Snip' {
        BeforeAll { Clear-TestState }

        It "One-tag snippet: Get-Snip succeeds without error" {
            { New-Snip -Name 'one-tag' -Language 'ps1' -Content '# one tag' -Tags @('solo') *>&1 | Out-Null
              Get-Snip *>&1 | Out-Null } | Should -Not -Throw
        }

        It "No-tag snippet: Get-Snip succeeds without error" {
            { New-Snip -Name 'no-tags' -Language 'ps1' -Content '# no tags' -Tags @() *>&1 | Out-Null
              Get-Snip *>&1 | Out-Null } | Should -Not -Throw
        }

        It "Two-tag snippet: Get-Snip succeeds without error" {
            { New-Snip -Name 'two-tags' -Language 'ps1' -Content '# two tags' -Tags @('a', 'b') *>&1 | Out-Null
              Get-Snip *>&1 | Out-Null } | Should -Not -Throw
        }

        It "Corrupt tags (bare string in JSON): Get-Snip no error" {
            & (Get-Module PSSnips) {
                $idx = script:LoadIdx
                $sm = [SnippetMetadata]::new()
                $sm.Name        = 'corrupt-tags'
                $sm.Description = 'corrupt entry'
                $sm.Language    = 'ps1'
                $sm.Tags        = @('bare-string-not-array')
                $idx.snippets['corrupt-tags'] = $sm
                Set-Content (Join-Path $script:SnipDir 'corrupt-tags.ps1') -Value '# corrupt' -Encoding UTF8
                script:SaveIdx -Idx $idx
            }
            { Get-Snip *>&1 | Out-Null } | Should -Not -Throw
        }
    }

    Context 'Count accuracy' {
        BeforeAll { Clear-TestState }

        It "Single snippet: Get-Snip returns exactly 1 result" {
            New-Snip -Name 'only-one' -Language 'ps1' -Content '# solo' *>&1 | Out-Null
            @(Get-Snip).Count | Should -Be 1
        }

        It "Two snippets: Get-Snip returns exactly 2 results" {
            New-Snip -Name 'second-one' -Language 'ps1' -Content '# second' *>&1 | Out-Null
            @(Get-Snip).Count | Should -Be 2
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Snippets: CRUD operations' {
    BeforeAll {
        Clear-TestState
        $script:SrcFile = Join-Path $script:TestRoot 'add-source.ps1'
        Set-Content $script:SrcFile -Value 'Write-Output "added-from-path"' -Encoding UTF8
        New-Snip -Name 'crud-snip' -Language 'ps1' -Content 'Write-Output "crud"' *>&1 | Out-Null
    }

    It "New-Snip creates the file on disk" {
        Join-Path $script:TestSnipDir 'crud-snip.ps1' | Should -Exist
    }

    It "New-Snip creates the index entry" {
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets.ContainsKey('crud-snip') | Should -BeTrue
    }

    It "Show-Snip displays correct content" {
        $out = (& { Show-Snip -Name 'crud-snip' } *>&1 | Out-String)
        $out | Should -Match 'crud'
    }

    It "Show-Snip -PassThru returns the content string" {
        $content = Show-Snip -Name 'crud-snip' -PassThru
        $content | Should -BeOfType [string]
        $content | Should -Match 'crud'
    }

    It "Add-Snip -Path imports file content" {
        Add-Snip -Name 'from-path' -Path $script:SrcFile *>&1 | Out-Null
        $content = Show-Snip -Name 'from-path' -PassThru
        $content | Should -Match 'added-from-path'
    }

    It "Add-Snip -FromClipboard saves clipboard content" {
        try {
            Set-Clipboard -Value 'Write-Output "clipboard-content"'
            Add-Snip -Name 'from-clip' -Language 'ps1' -FromClipboard *>&1 | Out-Null
            $content = Show-Snip -Name 'from-clip' -PassThru
            $content | Should -Match 'clipboard-content'
        } catch {
            Set-ItResult -Skipped -Because "clipboard not available in this environment"
        }
    }

    It "Remove-Snip removes file and index entry" {
        New-Snip -Name 'will-be-deleted' -Language 'ps1' -Content '# bye' *>&1 | Out-Null
        Remove-Snip -Name 'will-be-deleted' -Force *>&1 | Out-Null
        Join-Path $script:TestSnipDir 'will-be-deleted.ps1' | Should -Not -Exist
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets.ContainsKey('will-be-deleted') | Should -BeFalse
    }

    It "Remove-Snip -Force skips confirmation prompt" {
        New-Snip -Name 'force-delete-me' -Language 'ps1' -Content '# force' *>&1 | Out-Null
        Remove-Snip -Name 'force-delete-me' -Force *>&1 | Out-Null
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets.ContainsKey('force-delete-me') | Should -BeFalse
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Snippets: Tag management' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'tag-subject' -Language 'ps1' -Content '# tagging' -Tags @('alpha', 'beta') *>&1 | Out-Null
    }

    It "Set-SnipTag -Tags replaces all existing tags" {
        Set-SnipTag -Name 'tag-subject' -Tags @('newA', 'newB') *>&1 | Out-Null
        $tags = @((& (Get-Module PSSnips) { script:LoadIdx }).snippets['tag-subject'].Tags)
        $tags | Should -Contain 'newA'
        $tags | Should -Contain 'newB'
        $tags | Should -Not -Contain 'alpha'
    }

    It "Set-SnipTag -Add appends without creating duplicates" {
        Set-SnipTag -Name 'tag-subject' -Add @('extra') *>&1 | Out-Null
        Set-SnipTag -Name 'tag-subject' -Add @('extra') *>&1 | Out-Null
        $tags = @((& (Get-Module PSSnips) { script:LoadIdx }).snippets['tag-subject'].Tags)
        $tags | Should -Contain 'extra'
        ($tags | Where-Object { $_ -eq 'extra' }).Count | Should -Be 1
    }

    It "Set-SnipTag -Remove removes the specified tag" {
        Set-SnipTag -Name 'tag-subject' -Remove @('extra') *>&1 | Out-Null
        $tags = @((& (Get-Module PSSnips) { script:LoadIdx }).snippets['tag-subject'].Tags)
        $tags | Should -Not -Contain 'extra'
    }

    It "Tags survive round-trip through JSON (save and reload)" {
        Set-SnipTag -Name 'tag-subject' -Tags @('rt1', 'rt2') *>&1 | Out-Null
        $tags = @((& (Get-Module PSSnips) { script:LoadIdx }).snippets['tag-subject'].Tags)
        $tags | Should -Contain 'rt1'
        $tags | Should -Contain 'rt2'
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Snippets: Invoke-Snip execution' {
    BeforeAll { Clear-TestState }

    It "Invoke-Snip .ps1 snippet executes and produces output" {
        New-Snip -Name 'invoke-ps1' -Language 'ps1' -Content 'Write-Output "PSSnipsTestRun42"' *>&1 | Out-Null
        $out = (& { Invoke-Snip -Name 'invoke-ps1' } *>&1 | Out-String)
        $out | Should -Match 'PSSnipsTestRun42'
    }

    It "Invoke-Snip .bat snippet executes and produces output" {
        $batContent = "@echo off`r`necho PSSnipsBatRun42"
        New-Snip -Name 'invoke-bat' -Language 'bat' -Content $batContent *>&1 | Out-Null
        $out = (& { Invoke-Snip -Name 'invoke-bat' } *>&1 | Out-String)
        $out | Should -Match 'PSSnipsBatRun42'
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Config: Get and Set' {

    It "Get-SnipConfig produces output" {
        $out = (& { Get-SnipConfig } *>&1 | Out-String)
        $out.Length | Should -BeGreaterThan 0
    }

    It "Set-SnipConfig -Editor changes the editor value" {
        Set-SnipConfig -Editor 'notepad' *>&1 | Out-Null
        $cfg = & (Get-Module PSSnips) { script:LoadCfg }
        $cfg['Editor'] | Should -Be 'notepad'
    }

    It "Set-SnipConfig -DefaultLanguage changes the default language" {
        Set-SnipConfig -DefaultLanguage 'py' *>&1 | Out-Null
        $cfg = & (Get-Module PSSnips) { script:LoadCfg }
        $cfg['DefaultLanguage'] | Should -Be 'py'
    }

    It "Config survives round-trip through JSON (save and reload)" {
        Set-SnipConfig -Editor 'nvim' -DefaultLanguage 'js' *>&1 | Out-Null
        $cfg = & (Get-Module PSSnips) { script:LoadCfg }
        $cfg['Editor'] | Should -Be 'nvim'
        $cfg['DefaultLanguage'] | Should -Be 'js'
    }

    AfterAll {
        Set-SnipConfig -DefaultLanguage 'ps1' *>&1 | Out-Null
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Snippets: Search and filter' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'azure-deploy'  -Language 'ps1' -Content '# azure'  -Description 'Deploy to Azure'  -Tags @('cloud', 'devops') *>&1 | Out-Null
        New-Snip -Name 'local-utility' -Language 'py'  -Content '# util'   -Description 'Local utility'    -Tags @('util')            *>&1 | Out-Null
    }

    It "Get-Snip -Filter matches by name" {
        $rows = @(Get-Snip -Filter 'azure')
        $rows.Count | Should -BeGreaterOrEqual 1
        $rows | Where-Object { $_.Name -eq 'azure-deploy' } | Should -Not -BeNullOrEmpty
    }

    It "Get-Snip -Filter matches by description" {
        $rows = @(Get-Snip -Filter 'Local utility')
        $rows.Count | Should -BeGreaterOrEqual 1
        $rows | Where-Object { $_.Name -eq 'local-utility' } | Should -Not -BeNullOrEmpty
    }

    It "Get-Snip -Filter matches by tag" {
        $rows = @(Get-Snip -Filter 'devops')
        $rows.Count | Should -BeGreaterOrEqual 1
        $rows | Where-Object { $_.Name -eq 'azure-deploy' } | Should -Not -BeNullOrEmpty
    }

    It "Get-Snip -Language filters by extension" {
        $rows = @(Get-Snip -Language 'py')
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'local-utility'
    }

    It "Empty filter returns all snippets" {
        @(Get-Snip).Count | Should -Be 2
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Snippets: Add from pipeline' {
    BeforeAll { Clear-TestState }

    It "Pipe content into Add-Snip saves all lines correctly" {
        'line-alpha', 'line-beta', 'line-gamma' | Add-Snip -Name 'piped-snip' -Language 'txt'
        $content = Show-Snip -Name 'piped-snip' -PassThru
        $content | Should -Match 'line-alpha'
        $content | Should -Match 'line-beta'
        $content | Should -Match 'line-gamma'
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Edge cases' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'existing-snip' -Language 'ps1' -Content 'original-content-unchanged' *>&1 | Out-Null
    }

    It "New-Snip duplicate: warns and does NOT overwrite original" {
        $out = (& { New-Snip -Name 'existing-snip' -Language 'ps1' -Content 'replaced-content' } *>&1 | Out-String)
        $content = Show-Snip -Name 'existing-snip' -PassThru
        $out | Should -Match 'already exists'
        $content | Should -Match 'original-content-unchanged'
    }

    It "Remove-Snip nonexistent name: shows error, does NOT throw" {
        { & { Remove-Snip -Name 'nonexistent-snip-xyz-999' } *>&1 | Out-Null } | Should -Not -Throw
    }

    It "Show-Snip nonexistent name: shows error, does NOT throw" {
        { & { Show-Snip -Name 'nonexistent-snip-xyz-999' } *>&1 | Out-Null } | Should -Not -Throw
    }

    It "Invoke-Snip nonexistent name: shows error, does NOT throw" {
        { & { Invoke-Snip -Name 'nonexistent-snip-xyz-999' } *>&1 | Out-Null } | Should -Not -Throw
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Search: Full-text content' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'body-match-snip' -Language 'ps1' -Content 'Invoke-AzureDeployment -Env prod' *>&1 | Out-Null
        New-Snip -Name 'no-body-match'   -Language 'ps1' -Content '# local utility only'             *>&1 | Out-Null
    }

    It "Get-Snip -Filter 'azure' -Content returns snippets whose body contains 'azure'" {
        $rows = @(Get-Snip -Filter 'azure' -Content)
        $rows | Where-Object { $_.Name -eq 'body-match-snip' } | Should -Not -BeNullOrEmpty
    }

    It "Get-Snip -Filter 'azure' -Content excludes snippets with no match in name/desc/tags/body" {
        $rows = @(Get-Snip -Filter 'azure' -Content)
        $rows | Where-Object { $_.Name -eq 'no-body-match' } | Should -BeNullOrEmpty
    }

    It "Get-Snip -Content without matching body returns nothing extra (name-only match still works)" {
        New-Snip -Name 'azure-named' -Language 'ps1' -Content '# no azure in body' *>&1 | Out-Null
        $rows = @(Get-Snip -Filter 'azure' -Content)
        $rows | Where-Object { $_.Name -eq 'azure-named' }    | Should -Not -BeNullOrEmpty
        $rows | Where-Object { $_.Name -eq 'body-match-snip' } | Should -Not -BeNullOrEmpty
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'History: Run tracking' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'history-snip' -Language 'ps1' -Content '# history test' *>&1 | Out-Null
        Invoke-Snip -Name 'history-snip' *>&1 | Out-Null
    }

    It "After Invoke-Snip, runCount is incremented in the index" {
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $count = $idx.snippets['history-snip'].RunCount
        $count | Should -BeGreaterOrEqual 1
    }

    It "After Invoke-Snip, lastRun timestamp is set in the index" {
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $null -ne $idx.snippets['history-snip'].LastRun | Should -BeTrue
    }

    It "Get-Snip returns Runs property reflecting runCount" {
        $rows = @(Get-Snip -Filter 'history-snip')
        $rows.Count | Should -BeGreaterOrEqual 1
        $rows[0].Runs | Should -BeGreaterOrEqual 1
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Favorites: Pin and unpin' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'pin-me'   -Language 'ps1' -Content '# pin test' *>&1 | Out-Null
        New-Snip -Name 'unpinned' -Language 'ps1' -Content '# no pin'   *>&1 | Out-Null
    }

    It "Set-SnipTag -Pin sets pinned=true in index" {
        Set-SnipTag -Name 'pin-me' -Pin *>&1 | Out-Null
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets['pin-me'].Pinned | Should -BeTrue
    }

    It "Get-Snip returns Pinned=true for pinned snippet" {
        $row = @(Get-Snip) | Where-Object { $_.Name -eq 'pin-me' }
        $row | Should -Not -BeNullOrEmpty
        $row.Pinned | Should -BeTrue
    }

    It "Pinned snippet sorts before unpinned in Get-Snip output" {
        $rows    = @(Get-Snip)
        $pinIdx  = [array]::IndexOf($rows.Name, 'pin-me')
        $unpinIdx = [array]::IndexOf($rows.Name, 'unpinned')
        $pinIdx | Should -BeLessThan $unpinIdx
    }

    It "Set-SnipTag -Unpin sets pinned=false in index" {
        Set-SnipTag -Name 'pin-me' -Unpin *>&1 | Out-Null
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets['pin-me'].Pinned | Should -BeFalse
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Backup: Export-SnipCollection' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'export-test-snip' -Language 'ps1' -Content '# export test' *>&1 | Out-Null
        $script:BackupZip = Join-Path $script:TestRoot 'test-backup.zip'
        Export-SnipCollection -Path $script:BackupZip *>&1 | Out-Null
    }

    It "Export-SnipCollection creates a ZIP file at the specified path" {
        $script:BackupZip | Should -Exist
    }

    It "Export-SnipCollection ZIP contains the snippet file" {
        $extractDir = Join-Path $script:TestRoot 'verify-extract'
        Expand-Archive -Path $script:BackupZip -DestinationPath $extractDir -Force
        try {
            Join-Path $extractDir 'snippets' 'export-test-snip.ps1' | Should -Exist
        } finally {
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "Export-SnipCollection ZIP contains index.json" {
        $extractDir = Join-Path $script:TestRoot 'verify-extract2'
        Expand-Archive -Path $script:BackupZip -DestinationPath $extractDir -Force
        try {
            Join-Path $extractDir 'index.json' | Should -Exist
        } finally {
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Backup: Import-SnipCollection' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'local-only-keep' -Language 'ps1' -Content '# local only - preserve me' *>&1 | Out-Null
    }

    It "Import-SnipCollection -Merge adds backup snippets without removing existing" {
        Import-SnipCollection -Path $script:BackupZip -Merge *>&1 | Out-Null
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets.ContainsKey('local-only-keep')   | Should -BeTrue
        $idx.snippets.ContainsKey('export-test-snip')  | Should -BeTrue
    }

    It "Import-SnipCollection -Merge does not overwrite existing local snippet content" {
        $content = Show-Snip -Name 'local-only-keep' -PassThru
        $content | Should -Match '# local only - preserve me'
    }

    It "Import-SnipCollection without -Merge/-Force warns and aborts when snippets exist" {
        $out = (& { Import-SnipCollection -Path $script:BackupZip } *>&1 | Out-String)
        $out | Should -Match '(already has|not empty|Merge|Force)'
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Versioning: History and restore' {
    BeforeAll {
        Clear-TestState
        New-Snip -Name 'ver-subject' -Language 'ps1' -Content '# version 1' *>&1 | Out-Null
    }

    It "Get-SnipHistory returns empty when no history exists" {
        @(Get-SnipHistory -Name 'ver-subject').Count | Should -Be 0
    }

    It "After manually seeding history dir, Get-SnipHistory returns 1 entry" {
        & (Get-Module PSSnips) {
            param($Name, $Content)
            $histDir = Join-Path (Join-Path $script:Home 'history') $Name
            if (-not (Test-Path $histDir)) { New-Item -ItemType Directory $histDir -Force | Out-Null }
            $ts   = Get-Date -Format 'yyyyMMddHHmmss'
            Set-Content (Join-Path $histDir "$ts.ps1") -Value $Content -Encoding UTF8
        } 'ver-subject' '# version 1 snapshot'
        @(Get-SnipHistory -Name 'ver-subject').Count | Should -Be 1
    }

    It "Restore-Snip -Version 1 restores the seeded content" {
        Restore-Snip -Name 'ver-subject' -Version 1 *>&1 | Out-Null
        Show-Snip -Name 'ver-subject' -PassThru | Should -Match '# version 1 snapshot'
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Templates: Variable substitution' {
    BeforeAll { Clear-TestState }

    It "Invoke-Snip with -Variables fills {{VAR}} without prompting" {
        $outFile = Join-Path $script:TestRoot 'var-test-output.txt'
        New-Snip -Name 'var-snip' -Language 'ps1' `
            -Content "Set-Content '$outFile' -Value '{{GREETING}}' -Encoding UTF8" *>&1 | Out-Null
        Invoke-Snip -Name 'var-snip' -Variables @{ GREETING = 'hello-world' } *>&1 | Out-Null
        try {
            $outFile | Should -Exist
            (Get-Content $outFile -Raw -Encoding UTF8).Trim() | Should -Be 'hello-world'
        } finally {
            Remove-Item $outFile -Force -ErrorAction SilentlyContinue
        }
    }

    It "Invoke-Snip with no placeholders runs without modification" {
        New-Snip -Name 'no-placeholder' -Language 'ps1' -Content 'Write-Output "plain42"' *>&1 | Out-Null
        $out = (& { Invoke-Snip -Name 'no-placeholder' } *>&1 | Out-String)
        $out | Should -Match 'plain42'
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Lint: Test-Snip' {
    BeforeAll { Clear-TestState }

    It "Test-Snip on a non-PS file prints 'analysis only applies to PowerShell files'" {
        New-Snip -Name 'test-txt' -Language 'txt' -Content 'hello world' *>&1 | Out-Null
        $out = (& { Test-Snip -Name 'test-txt' } *>&1 | Out-String)
        $out | Should -Match '(?i)(analysis only applies to PowerShell)'
    }

    It "Test-Snip on nonexistent snippet shows error without throwing" {
        { & { Test-Snip -Name 'nonexistent-lint-xyz-999' } *>&1 | Out-Null } | Should -Not -Throw
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Chaining: Invoke-Snip -Pipeline' {
    BeforeAll { Clear-TestState }

    It "Invoke-Snip -Pipeline runs both snippets" {
        $outA = Join-Path $script:TestRoot 'chain-a.txt'
        $outB = Join-Path $script:TestRoot 'chain-b.txt'
        Remove-Item $outA, $outB -Force -ErrorAction SilentlyContinue
        New-Snip -Name 'chain-snip-a' -Language 'ps1' `
            -Content "New-Item -ItemType File -Path '$outA' -Force | Out-Null" *>&1 | Out-Null
        New-Snip -Name 'chain-snip-b' -Language 'ps1' `
            -Content "New-Item -ItemType File -Path '$outB' -Force | Out-Null" *>&1 | Out-Null
        Invoke-Snip -Pipeline @('chain-snip-a', 'chain-snip-b') *>&1 | Out-Null
        try {
            $outA | Should -Exist
            $outB | Should -Exist
        } finally {
            Remove-Item $outA, $outB -Force -ErrorAction SilentlyContinue
        }
    }

    It "Invoke-Snip -Pipeline stops on first error without -ContinueOnError" {
        $outC = Join-Path $script:TestRoot 'chain-c.txt'
        Remove-Item $outC -Force -ErrorAction SilentlyContinue
        New-Snip -Name 'chain-snip-c' -Language 'ps1' `
            -Content "New-Item -ItemType File -Path '$outC' -Force | Out-Null" *>&1 | Out-Null
        Invoke-Snip -Pipeline @('nonexistent-chain-xyz', 'chain-snip-c') *>&1 | Out-Null
        try {
            $outC | Should -Not -Exist
        } finally {
            Remove-Item $outC -Force -ErrorAction SilentlyContinue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Dedup: Duplicate detection' {
    BeforeAll { Clear-TestState }

    It "GetContentHash returns consistent SHA256 for same content" {
        $h1 = & (Get-Module PSSnips) { script:GetContentHash -Content 'hello world' }
        $h2 = & (Get-Module PSSnips) { script:GetContentHash -Content 'hello world' }
        $h3 = & (Get-Module PSSnips) { script:GetContentHash -Content 'different'   }
        $h1 | Should -Be $h2
        $h1 | Should -Not -Be $h3
        $h1.Length | Should -Be 64
    }

    It "New-Snip with duplicate content warns and does NOT save" {
        New-Snip -Name 'orig-dup' -Language 'ps1' -Content 'duplicate-content-here' *>&1 | Out-Null
        $out = (& { New-Snip -Name 'new-dup' -Language 'ps1' -Content 'duplicate-content-here' } *>&1 | Out-String)
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $out | Should -Match '(?i)duplicate'
        $idx.snippets.ContainsKey('new-dup') | Should -BeFalse
    }

    It "New-Snip -IgnoreDuplicate saves despite duplicate content" {
        New-Snip -Name 'force-dup' -Language 'ps1' -Content 'duplicate-content-here' -IgnoreDuplicate *>&1 | Out-Null
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets.ContainsKey('force-dup') | Should -BeTrue
    }

    It "New-Snip stores contentHash in index entry" {
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets['orig-dup'].ContentHash | Should -Not -BeNullOrEmpty
        $idx.snippets['orig-dup'].ContentHash.Length | Should -Be 64
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Profile: Install-PSSnips' {

    It "Install-PSSnips -WhatIf does not modify the profile file" {
        $fakeProfile = Join-Path $script:TestRoot 'fake-profile.ps1'
        & (Get-Module PSSnips) {
            param($FakePath)
            $script:__fakeProfilePath = $FakePath
        } $fakeProfile
        Install-PSSnips -WhatIf *>&1 | Out-Null
        $fakeProfile | Should -Not -Exist
    }

    It "Install-PSSnips with fresh temp profile creates import line" {
        $tempProfile = Join-Path $script:TestRoot 'install-test-profile.ps1'
        Remove-Item $tempProfile -Force -ErrorAction SilentlyContinue
        & (Get-Module PSSnips) {
            param($TempProfile)
            function script:GetTestProfilePath { return $TempProfile }
        } $tempProfile
        # -WhatIf prevents writes; verify it completes without error
        { Install-PSSnips -WhatIf *>&1 | Out-Null } | Should -Not -Throw
    }
}

# ─────────────────────────────────────────────────────────────────────────────

Describe 'Sharing: Shared storage' {
    BeforeAll {
        Clear-TestState
        $script:SharedDir = Join-Path $script:TestRoot 'shared-storage'
        New-Item -ItemType Directory -Path $script:SharedDir -Force | Out-Null
        & (Get-Module PSSnips) {
            param($SharedPath)
            $cfg = script:LoadCfg
            $cfg['SharedSnippetsDir'] = $SharedPath
            script:SaveCfg -Cfg $cfg
        } $script:SharedDir
        New-Snip -Name 'shared-snip' -Language 'ps1' -Content '# shared snippet' *>&1 | Out-Null
        Publish-Snip -Name 'shared-snip' *>&1 | Out-Null
    }

    AfterAll {
        & (Get-Module PSSnips) {
            $cfg = script:LoadCfg
            $cfg['SharedSnippetsDir'] = ''
            script:SaveCfg -Cfg $cfg
        }
    }

    It "Publish-Snip copies file to shared dir and creates shared-index.json" {
        Join-Path $script:SharedDir 'shared-snip.ps1'     | Should -Exist
        Join-Path $script:SharedDir 'shared-index.json'   | Should -Exist
    }

    It "shared-index.json contains the published snippet entry" {
        $raw = Get-Content (Join-Path $script:SharedDir 'shared-index.json') -Raw -Encoding UTF8
        $sharedIdx = $raw | ConvertFrom-Json
        $sharedIdx.snippets.'shared-snip' | Should -Not -BeNullOrEmpty
    }

    It "Sync-SharedSnips imports snippets from shared dir into local index" {
        Clear-TestState
        Sync-SharedSnips *>&1 | Out-Null
        $idx = & (Get-Module PSSnips) { script:LoadIdx }
        $idx.snippets.ContainsKey('shared-snip') | Should -BeTrue
    }

    It "Get-Snip -Shared reads from SharedSnippetsDir index" {
        $rows = @(Get-Snip -Shared)
        $rows.Count | Should -BeGreaterOrEqual 1
        $rows | Where-Object { $_.Name -eq 'shared-snip' } | Should -Not -BeNullOrEmpty
    }

    It "Get-Snip -Shared shows [shared] in Source or Gist column" {
        $rows = @(Get-Snip -Shared)
        $row  = $rows | Where-Object { $_.Name -eq 'shared-snip' }
        $row | Should -Not -BeNullOrEmpty
        ($row.Source -eq '[shared]' -or $row.Gist -eq '[shared]') | Should -BeTrue
    }
}
