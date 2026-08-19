#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Tests for tools/Update-PfbEmptyPipelineGuards.ps1, the generator that inserts one
    empty-pipeline guard statement into every collect-then-request public cmdlet.
.DESCRIPTION
    Notes on deliberate choices here:

    * Every path derives from $PSScriptRoot. The Pester runner does not run with the repo
      root as its working directory, so a CWD-relative path silently resolves elsewhere.

    * The population is re-derived from the source AST by the generator itself. This file
      never reads the outer census CSV: a future cmdlet added to Public/ must be discovered,
      not compared against a frozen list.

    * Synthetic fixtures are parsed but never executed, so they reference $Array and
      Invoke-PfbApiRequest without either existing.

    * The "Unnamed end block" fixture is the trap this whole predicate exists for: the
      parser SYNTHESISES an end block for a function that declared no named blocks at all,
      so `$null -ne $Body.EndBlock` alone is true for nearly every function in the module.
      Only a NAMED end block paired with a process block is a collect-then-request shape.

    * The real-tree fixed point is asserted with -WhatIf, which reports what WOULD change
      and writes nothing -- the same strength as write-twice-and-compare with no chance of
      dirtying tracked Public/ files when it fails.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:generator = Join-Path $script:repoRoot 'tools/Update-PfbEmptyPipelineGuards.ps1'
    $script:guard = 'if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }'

    function New-GuardFixture {
        param([string]$Root, [string]$Name, [string[]]$Lines, [string]$Newline = "`n")
        $public = Join-Path $Root 'Public'
        New-Item -ItemType Directory -Path $public -Force | Out-Null
        $path = Join-Path $public "$Name.ps1"
        [System.IO.File]::WriteAllText(
            $path,
            ($Lines -join $Newline) + $Newline,
            (New-Object System.Text.UTF8Encoding($false)))
        return $path
    }

    # Byte-exact "unchanged on disk" evidence, as one comparable string. Comparing the raw
    # byte arrays with Should -Be works but reports a several-hundred-element diff on
    # failure; the hex signature fails in one readable line and is just as exact.
    function Get-FixtureByteSignature {
        param([string]$Path)
        [System.BitConverter]::ToString([System.IO.File]::ReadAllBytes($Path))
    }

    # A plain collect-then-request shape: begin/process/end, one request in the end block.
    function Get-NormalFixtureLines {
        param([string]$FunctionName = 'Get-FixtureNormal')
        @(
            "function $FunctionName {"
            '    [CmdletBinding()]'
            '    param('
            '        [Parameter(ValueFromPipeline)] [string[]]$Name,'
            '        [Parameter()] [PSCustomObject]$Array'
            '    )'
            '    begin { $allNames = @() }'
            '    process { if ($Name) { $allNames += $Name } }'
            '    end {'
            '        $queryParams = @{}'
            '        if ($allNames.Count -gt 0) { $queryParams[''names''] = $allNames -join '','' }'
            "        Invoke-PfbApiRequest -Array `$Array -Method GET -Endpoint 'fixtures' -QueryParams `$queryParams"
            '    }'
            '}'
        )
    }
}

Describe 'Update-PfbEmptyPipelineGuards - fixture shapes' {

    It 'inserts exactly one guard immediately before the request in a normal function' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureNormal' -Lines (Get-NormalFixtureLines)

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 1
        @($summary.AlreadyPresent).Count | Should -Be 0
        @($summary.SkippedNeedsHuman).Count | Should -Be 0

        $text = [System.IO.File]::ReadAllText($file)
        $text.Contains($script:guard) | Should -BeTrue

        # Placement and indentation: the guard is the line directly above the request, at
        # the request's own indent.
        $lines = $text -split "`n"
        $guardIndex = [array]::IndexOf($lines, '        ' + $script:guard)
        $guardIndex | Should -BeGreaterThan 0
        $lines[$guardIndex + 1] | Should -BeLike '        Invoke-PfbApiRequest *'

        # Exactly one guard, not one per parse pass.
        ([regex]::Matches($text, [regex]::Escape($script:guard))).Count | Should -Be 1
    }

    It 'inserts before the containing top-level statement when the request is nested in a try' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureTry' -Lines @(
            'function Get-FixtureTry {'
            '    [CmdletBinding()]'
            '    param('
            '        [Parameter(ValueFromPipeline)] [string[]]$Name,'
            '        [Parameter()] [PSCustomObject]$Array'
            '    )'
            '    begin { $allNames = @() }'
            '    process { if ($Name) { $allNames += $Name } }'
            '    end {'
            '        $queryParams = @{}'
            '        try {'
            "            Invoke-PfbApiRequest -Array `$Array -Method GET -Endpoint 'fixtures' -QueryParams `$queryParams"
            '        }'
            '        catch { throw }'
            '    }'
            '}'
        )

        $summary = & $script:generator -PublicRoot $root -Confirm:$false
        @($summary.Inserted).Count | Should -Be 1

        $lines = [System.IO.File]::ReadAllText($file) -split "`n"
        $guardIndex = [array]::IndexOf($lines, '        ' + $script:guard)
        $guardIndex | Should -BeGreaterThan 0
        # The guard dominates the whole try statement rather than sitting inside it.
        $lines[$guardIndex + 1] | Should -Be '        try {'
    }

    It 'leaves a function with no process block untouched' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureNoProcess' -Lines @(
            'function Get-FixtureNoProcess {'
            '    [CmdletBinding()]'
            '    param([Parameter()] [PSCustomObject]$Array)'
            '    begin { $queryParams = @{} }'
            '    end {'
            "        Invoke-PfbApiRequest -Array `$Array -Method GET -Endpoint 'fixtures' -QueryParams `$queryParams"
            '    }'
            '}'
        )
        $before = Get-FixtureByteSignature $file

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 0
        @($summary.SkippedNeedsHuman).Count | Should -Be 0
        Get-FixtureByteSignature $file | Should -Be $before
    }

    It 'leaves a function whose end block is only the parser-synthesised Unnamed block untouched' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureUnnamedEnd' -Lines @(
            'function Get-FixtureUnnamedEnd {'
            '    [CmdletBinding()]'
            '    param([Parameter()] [PSCustomObject]$Array)'
            '    $queryParams = @{}'
            "    Invoke-PfbApiRequest -Array `$Array -Method GET -Endpoint 'fixtures' -QueryParams `$queryParams"
            '}'
        )
        $before = Get-FixtureByteSignature $file

        # Pin the trap itself: this function DOES have a non-null EndBlock. Only the Unnamed
        # flag distinguishes it, which is why the predicate cannot be a null check alone.
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
        $fn = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true))[0]
        $null -eq $fn.Body.EndBlock | Should -BeFalse
        $fn.Body.EndBlock.Unnamed | Should -BeTrue

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 0
        @($summary.SkippedNeedsHuman).Count | Should -Be 0
        Get-FixtureByteSignature $file | Should -Be $before
    }

    It 'routes a function with two requests in its end block to SkippedNeedsHuman, unedited' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureTwoCalls' -Lines @(
            'function Get-FixtureTwoCalls {'
            '    [CmdletBinding()]'
            '    param('
            '        [Parameter(ValueFromPipeline)] [string[]]$Name,'
            '        [Parameter()] [PSCustomObject]$Array'
            '    )'
            '    begin { $allNames = @() }'
            '    process { if ($Name) { $allNames += $Name } }'
            '    end {'
            '        $queryParams = @{}'
            '        try {'
            "            Invoke-PfbApiRequest -Array `$Array -Method GET -Endpoint 'primary' -QueryParams `$queryParams"
            '        }'
            '        catch {'
            "            Invoke-PfbApiRequest -Array `$Array -Method GET -Endpoint 'fallback' -QueryParams `$queryParams"
            '        }'
            '    }'
            '}'
        )
        $before = Get-FixtureByteSignature $file

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 0
        @($summary.SkippedNeedsHuman).Count | Should -Be 1
        @($summary.SkippedNeedsHuman)[0] | Should -Be $file
        Get-FixtureByteSignature $file | Should -Be $before
    }

    It 'routes a SupportsShouldProcess function to SkippedNeedsHuman, unedited' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Remove-FixtureThing' -Lines @(
            'function Remove-FixtureThing {'
            "    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]"
            '    param('
            '        [Parameter(ValueFromPipeline)] [string[]]$Name,'
            '        [Parameter()] [PSCustomObject]$Array'
            '    )'
            '    begin { $allNames = @() }'
            '    process { if ($Name) { $allNames += $Name } }'
            '    end {'
            '        $queryParams = @{}'
            "        if (`$PSCmdlet.ShouldProcess('x', 'Delete')) {"
            "            Invoke-PfbApiRequest -Array `$Array -Method DELETE -Endpoint 'fixtures' -QueryParams `$queryParams"
            '        }'
            '    }'
            '}'
        )
        $before = Get-FixtureByteSignature $file

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 0
        @($summary.SkippedNeedsHuman).Count | Should -Be 1
        Get-FixtureByteSignature $file | Should -Be $before
    }

    It 'routes a file on the explicit human-review list to SkippedNeedsHuman even when its shape is ordinary' {
        # Get-PfbRemoteArray writes current_fleet_only on BOTH branches of an if/else, so its
        # query hashtable is never empty at the request and a generated guard in the usual
        # position would be inert. Its guard is placed by hand, above that write.
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-PfbRemoteArray' `
            -Lines (Get-NormalFixtureLines -FunctionName 'Get-PfbRemoteArray')
        $before = Get-FixtureByteSignature $file

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 0
        @($summary.SkippedNeedsHuman).Count | Should -Be 1
        @($summary.SkippedNeedsHuman)[0] | Should -Be $file
        Get-FixtureByteSignature $file | Should -Be $before
    }

    It 'reports a file that already carries the exact guard as AlreadyPresent and does not rewrite it' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $lines = @(Get-NormalFixtureLines -FunctionName 'Get-FixtureGuarded')
        # Splice the guard in above the request line, exactly where the generator puts it.
        $requestIndex = [array]::IndexOf($lines, ($lines | Where-Object { $_ -like '*Invoke-PfbApiRequest*' } | Select-Object -First 1))
        $withGuard = @($lines[0..($requestIndex - 1)]) + @('        ' + $script:guard) + @($lines[$requestIndex..($lines.Count - 1)])
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureGuarded' -Lines $withGuard
        $before = Get-FixtureByteSignature $file

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.Inserted).Count | Should -Be 0
        @($summary.AlreadyPresent).Count | Should -Be 1
        @($summary.SkippedNeedsHuman).Count | Should -Be 0
        Get-FixtureByteSignature $file | Should -Be $before
    }

    It 'recognises an already-guarded file EVEN IF it is a human-review outlier' {
        # Order is load-bearing: existing-guard first, human-review list second, shape third.
        # If the list were consulted first, the hand-edited outliers would report
        # SkippedNeedsHuman forever and the drift fixed point could never be reached.
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $lines = @(Get-NormalFixtureLines -FunctionName 'Get-PfbRemoteArray')
        $requestIndex = [array]::IndexOf($lines, ($lines | Where-Object { $_ -like '*Invoke-PfbApiRequest*' } | Select-Object -First 1))
        $withGuard = @($lines[0..($requestIndex - 1)]) + @('        ' + $script:guard) + @($lines[$requestIndex..($lines.Count - 1)])
        $file = New-GuardFixture -Root $root -Name 'Get-PfbRemoteArray' -Lines $withGuard

        $summary = & $script:generator -PublicRoot $root -Confirm:$false

        @($summary.AlreadyPresent).Count | Should -Be 1
        @($summary.SkippedNeedsHuman).Count | Should -Be 0
    }

    It 'is idempotent: a second run over the same fixture root inserts nothing' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureIdempotent' `
            -Lines (Get-NormalFixtureLines -FunctionName 'Get-FixtureIdempotent')

        & $script:generator -PublicRoot $root -Confirm:$false | Out-Null
        $afterFirst = Get-FixtureByteSignature $file

        $second = & $script:generator -PublicRoot $root -Confirm:$false

        @($second.Inserted).Count | Should -Be 0
        @($second.AlreadyPresent).Count | Should -Be 1
        Get-FixtureByteSignature $file | Should -Be $afterFirst
    }

    It 'writes nothing under -WhatIf but still reports what it would insert' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureWhatIf' `
            -Lines (Get-NormalFixtureLines -FunctionName 'Get-FixtureWhatIf')
        $before = Get-FixtureByteSignature $file

        $summary = & $script:generator -PublicRoot $root -WhatIf

        @($summary.Inserted).Count | Should -Be 1
        Get-FixtureByteSignature $file | Should -Be $before
    }
}

Describe 'Update-PfbEmptyPipelineGuards - encoding and line endings' {

    It 'preserves LF line endings and writes no BOM' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureLf' `
            -Lines (Get-NormalFixtureLines -FunctionName 'Get-FixtureLf') -Newline "`n"

        & $script:generator -PublicRoot $root -Confirm:$false | Out-Null

        $text = [System.IO.File]::ReadAllText($file)
        $text.Contains("`r`n") | Should -BeFalse
        $text.Contains($script:guard) | Should -BeTrue

        $bytes = [System.IO.File]::ReadAllBytes($file)
        # 0xEF 0xBB 0xBF is the UTF-8 BOM. No Public/*.ps1 carries one and the generator
        # must not introduce one.
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'preserves CRLF line endings and writes no BOM' {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $file = New-GuardFixture -Root $root -Name 'Get-FixtureCrlf' `
            -Lines (Get-NormalFixtureLines -FunctionName 'Get-FixtureCrlf') -Newline "`r`n"

        & $script:generator -PublicRoot $root -Confirm:$false | Out-Null

        $text = [System.IO.File]::ReadAllText($file)
        $text.Contains($script:guard) | Should -BeTrue
        # Every LF in the file is part of a CRLF pair: no line was rewritten with a bare LF.
        ([regex]::Matches($text, "`n")).Count | Should -Be ([regex]::Matches($text, "`r`n")).Count

        $bytes = [System.IO.File]::ReadAllBytes($file)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }
}

Describe 'Update-PfbEmptyPipelineGuards - human-review list integrity' {

    It 'throws when a human-review entry matches no file in the real tree' {
        # The list is a [string[]] of leaf names. If a listed cmdlet is renamed or deleted,
        # the entry must fail loudly rather than quietly protect nothing. Scoped to the real
        # tree only, so synthetic fixture roots are not required to contain every entry.
        { & $script:generator -WhatIf -HumanReviewFile 'Get-PfbNoSuchCmdlet.ps1' } |
            Should -Throw -ExpectedMessage '*Get-PfbNoSuchCmdlet.ps1*'
    }
}

Describe 'Update-PfbEmptyPipelineGuards - real tree' {

    It 'is at a fixed point: a -WhatIf run over Public/ reports zero insertions and 130 guarded files' {
        # Derived from the source AST on every run, so a newly added collect-then-request
        # cmdlet raises this count and fails here rather than shipping unguarded.
        $summary = & $script:generator -WhatIf

        @($summary.Inserted).Count | Should -Be 0
        @($summary.AlreadyPresent).Count | Should -Be 130
        @($summary.SkippedNeedsHuman).Count | Should -Be 0
    }
}
