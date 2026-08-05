#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
}

Describe 'PfbContext object' {
    Context 'wire composition' {
        It 'renders a bare name for Array/Object' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'FB-B' -Kind 'Array' -Form 'Object'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'FB-B'
            }
        }
        It 'renders a bare name for Fleet/Object' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'Object'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'cc-test-fleet'
            }
        }
        It 'appends .arrays for Fleet/AllArrays' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'cc-test-fleet' -Kind 'Fleet' -Form 'AllArrays'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'cc-test-fleet.arrays'
            }
        }
        It 'appends .arrays for TopologyGroup/AllArrays' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'region-1' -Kind 'TopologyGroup' -Form 'AllArrays'
                ConvertTo-PfbContextWireValue -Entry $e | Should -Be 'region-1.arrays'
            }
        }
        It 'uses a lower-case .arrays suffix, which is case-sensitive on the wire' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'x' -Kind 'Fleet' -Form 'AllArrays'
                ConvertTo-PfbContextWireValue -Entry $e | Should -MatchExactly '\.arrays$'
            }
        }
    }
    Context 'invalid compositions' {
        It 'rejects Array + AllArrays because an array has no members' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'FB-B' -Kind 'Array' -Form 'AllArrays'
                { Assert-PfbContextEntryComposition -Entry $e } | Should -Throw -ExpectedMessage '*an array has no members*'
            }
        }
        It 'rejects TopologyGroup + Object because no endpoint accepts a bare group name' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'region-1' -Kind 'TopologyGroup' -Form 'Object'
                { Assert-PfbContextEntryComposition -Entry $e } | Should -Throw -ExpectedMessage '*<name>.arrays*'
            }
        }
        It 'accepts every valid pair' {
            InModuleScope PureStorageFlashBladePowerShell {
                foreach ($pair in @(@('Array','Object'), @('Fleet','Object'), @('Fleet','AllArrays'), @('TopologyGroup','AllArrays'))) {
                    $e = New-PfbContextEntry -Name 'n' -Kind $pair[0] -Form $pair[1]
                    { Assert-PfbContextEntryComposition -Entry $e } | Should -Not -Throw
                }
            }
        }
    }
    Context 'defaults and shape' {
        It 'defaults Kind to Array and Form to Object' {
            InModuleScope PureStorageFlashBladePowerShell {
                $e = New-PfbContextEntry -Name 'FB-B'
                $e.Kind | Should -Be 'Array'
                $e.Form | Should -Be 'Object'
            }
        }
        It 'keeps Kind per-entry, not one scalar for the context' {
            InModuleScope PureStorageFlashBladePowerShell {
                $c = New-PfbContext -Entries @(
                    (New-PfbContextEntry -Name 'FB-B' -Kind 'Array'),
                    (New-PfbContextEntry -Name 'f' -Kind 'Fleet')
                )
                @($c.Entries).Count | Should -Be 2
                $c.Entries[0].Kind   | Should -Be 'Array'
                $c.Entries[1].Kind   | Should -Be 'Fleet'
            }
        }
        It 'reserves AllowErrors as tri-state, defaulting to null (Phase 2 surfaces it)' {
            InModuleScope PureStorageFlashBladePowerShell {
                (New-PfbContext -Entries @((New-PfbContextEntry -Name 'x'))).AllowErrors | Should -BeNullOrEmpty
            }
        }
        It 'normalises a string[] into entries of one kind' {
            InModuleScope PureStorageFlashBladePowerShell {
                $entries = ConvertTo-PfbContextEntryList -Name @('FB-B','FB-C') -Kind 'Array' -Form 'Object'
                @($entries).Count            | Should -Be 2
                $entries[1].Name             | Should -Be 'FB-C'
            }
        }
    }
}

Describe 'PfbContext Kind/Form ValidateSet vocabulary' {
    # ValidateSet cannot take a variable in PowerShell, so the Kind and Form vocabularies
    # must be duplicated as literals at every parameter that surfaces them (2 private sites
    # today, plus one per public cmdlet added later). This meta-test is what keeps those
    # copies honest, and it must cover new sites with no edit here -- so it discovers them
    # by parsing the module's sources rather than from any hardcoded list of files or
    # functions.
    #
    # Scope: every .ps1 under Private/ and Public/ -- i.e. all shipped module source.
    # Tests/ and tools/ are excluded: they are not loaded by the module and a fixture or
    # generator is allowed its own unrelated sets.
    #
    # Discriminator: the module has many unrelated ValidateSets, so each discovered set is
    # classified by its own contents, not by the file or parameter name (a parameter could
    # be renamed, and a single file can legitimately hold both a Kind and a Form site).
    # A set containing 'Fleet' is a Kind set; a set containing 'AllArrays' is a Form set.
    # Those two tokens appear in no other vocabulary in the module, and classifying
    # per-attribute means a file holding both is handled naturally. Any set matching
    # neither token is ignored.
    BeforeAll {
        $moduleRoot = (Resolve-Path "$PSScriptRoot/..").Path
        $sourceFiles = @(
            'Private', 'Public' | ForEach-Object {
                $dir = Join-Path $moduleRoot $_
                if (Test-Path $dir) { Get-ChildItem -LiteralPath $dir -Filter '*.ps1' -Recurse -File }
            }
        )

        $script:KindSites = @()
        $script:FormSites = @()

        foreach ($file in $sourceFiles) {
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $file.FullName, [ref]$tokens, [ref]$errors)
            if (-not $ast) { continue }

            $attrs = $ast.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.AttributeAst] -and
                $n.TypeName.Name -match '^ValidateSet(Attribute)?$'
            }, $true)

            foreach ($attr in $attrs) {
                $values = @(
                    $attr.PositionalArguments |
                        Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } |
                        ForEach-Object { $_.Value }
                )
                if ($values.Count -eq 0) { continue }
                $site = [PSCustomObject]@{
                    File   = $file.FullName.Substring($moduleRoot.Length).TrimStart('\', '/')
                    Line   = $attr.Extent.StartLineNumber
                    Values = $values
                }
                if ($values -contains 'Fleet')     { $script:KindSites += $site }
                elseif ($values -contains 'AllArrays') { $script:FormSites += $site }
            }
        }
    }

    It 'finds at least one Kind site and one Form site (a silent no-match scan would assert nothing)' {
        # Mandatory guard: without it, a scanner that matched nothing would pass forever.
        @($script:KindSites).Count | Should -BeGreaterThan 0 -Because 'the scan must actually locate the Kind ValidateSet literals'
        @($script:FormSites).Count | Should -BeGreaterThan 0 -Because 'the scan must actually locate the Form ValidateSet literals'
    }

    It 'has every Kind ValidateSet in agreement' {
        $distinct = @($script:KindSites | ForEach-Object { ($_.Values | Sort-Object) -join ',' } | Sort-Object -Unique)
        $detail = ($script:KindSites | ForEach-Object { "$($_.File):$($_.Line) => $(($_.Values | Sort-Object) -join ',')" }) -join "`n"
        @($distinct).Count | Should -Be 1 -Because "all Kind ValidateSets must list the same values:`n$detail"
    }

    It 'has every Form ValidateSet in agreement' {
        $distinct = @($script:FormSites | ForEach-Object { ($_.Values | Sort-Object) -join ',' } | Sort-Object -Unique)
        $detail = ($script:FormSites | ForEach-Object { "$($_.File):$($_.Line) => $(($_.Values | Sort-Object) -join ',')" }) -join "`n"
        @($distinct).Count | Should -Be 1 -Because "all Form ValidateSets must list the same values:`n$detail"
    }
}
