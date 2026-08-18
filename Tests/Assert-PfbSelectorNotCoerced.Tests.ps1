#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
    $script:fakeArray = [PSCustomObject]@{
        Endpoint   = 'fb.example.test'
        ApiVersion = '2.0'
        AuthToken  = 'x'
    }
}

Describe 'Assert-PfbSelectorNotCoerced (#90)' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'accepts a plain name' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value 'nfs-export-01' -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Not -Throw
        }
    }

    It 'accepts an array of plain names' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value @('a', 'b', 'c') -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Not -Throw
        }
    }

    It 'accepts $null, because an unbound parameter is not a defect' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value $null -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Not -Throw
        }
    }

    It 'accepts an empty array' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value @() -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Not -Throw
        }
    }

    It 'emits nothing to the success stream on success' {
        InModuleScope PureStorageFlashBladePowerShell {
            $out = Assert-PfbSelectorNotCoerced -Value 'nfs-export-01' -ParameterName 'PolicyName' -Hint 'h'
            $out | Should -BeNullOrEmpty
        }
    }

    It 'throws on a stringified object' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value '@{name=nfs-01; rules=}' -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Throw
        }
    }

    It 'puts the exact substring "stringified object" in the message, which is how the rail classifies Guarded' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value '@{name=nfs-01}' -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Throw -ExpectedMessage '*stringified object*'
        }
    }

    It 'names the parameter with its leading dash' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value '@{name=nfs-01}' -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Throw -ExpectedMessage '*-PolicyName*'
        }
    }

    It 'names the parameter it was actually given, not a hardcoded one' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value '@{name=b1}' -ParameterName 'BucketName' -Hint 'h' } |
                Should -Throw -ExpectedMessage '*-BucketName*'
        }
    }

    It 'carries the caller-supplied hint through to the message' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value '@{name=nfs-01}' -ParameterName 'PolicyName' `
                    -Hint 'Pipe the policy name instead, e.g. Get-PfbNfsExportPolicy | Select-Object -ExpandProperty name | Get-PfbNfsExportRule.' } |
                Should -Throw -ExpectedMessage '*Get-PfbNfsExportPolicy*'
        }
    }

    It 'leaves no unexpanded format placeholder in the message' {
        # Guards the -f precedence trap: '+' binds looser than the format operator, so a
        # message split across concatenated literals formats only the last one and ships
        # a literal {0} to the caller.
        InModuleScope PureStorageFlashBladePowerShell {
            $captured = $null
            try {
                Assert-PfbSelectorNotCoerced -Value '@{name=nfs-01}' -ParameterName 'PolicyName' -Hint 'pipe .name'
            } catch {
                $captured = $_.Exception.Message
            }
            $captured | Should -Not -BeNullOrEmpty
            $captured.Contains('stringified object') | Should -BeTrue
            $captured.Contains('{0}') | Should -BeFalse
            $captured.Contains('{1}') | Should -BeFalse
            $captured.Contains('{2}') | Should -BeFalse
        }
    }

    It 'checks every element of an array, not just the first' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value @('good-name', '@{name=nfs-01}') -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Throw -ExpectedMessage '*stringified object*'
        }
    }

    It 'ignores a non-string value' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value ([PSCustomObject]@{ name = 'nfs-01' }) `
                    -ParameterName 'PolicyName' -Hint 'h' } | Should -Not -Throw
        }
    }

    It 'detects a stringified object whose text contains a backtick' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbSelectorNotCoerced -Value ("@{name=nfs" + [char]96 + "01}") -ParameterName 'PolicyName' -Hint 'h' } |
                Should -Throw -ExpectedMessage '*stringified object*'
        }
    }

    It 'rejects a hashtable piped into an actual selector cmdlet before any request' {
        { , @{ name = 'nfs-policy-1' } |
            Get-PfbNfsExportRule -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*stringified object*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'rejects a generic dictionary piped into an actual selector cmdlet before any request' {
        $dictionary = [System.Collections.Generic.Dictionary[string, string]]::new()
        $dictionary['name'] = 'nfs-policy-1'

        { , $dictionary |
            Get-PfbNfsExportRule -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*stringified object*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'rejects a PSCustomObject piped into an actual selector cmdlet before any request' {
        { [PSCustomObject]@{ name = 'nfs-policy-1' } |
            Get-PfbNfsExportRule -Array $script:fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*stringified object*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'accepts a legitimate piped name' {
        { 'prod-policy' | Get-PfbNfsExportRule -Array $script:fakeArray -ErrorAction Stop } |
            Should -Not -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'prod-policy'
        }
    }

    It 'accepts a legitimate piped name that looks type-ish' {
        { 'System.backup' | Get-PfbNfsExportRule -Array $script:fakeArray -ErrorAction Stop } |
            Should -Not -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['policy_names'] -eq 'System.backup'
        }
    }
}
