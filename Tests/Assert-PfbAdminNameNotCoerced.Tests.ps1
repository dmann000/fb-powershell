#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Assert-PfbAdminNameNotCoerced (#99)' {

    It 'accepts a plain administrator name' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbAdminNameNotCoerced -Value 'ops-admin' } | Should -Not -Throw
        }
    }

    It 'emits nothing to the success stream on success' {
        InModuleScope PureStorageFlashBladePowerShell {
            $out = Assert-PfbAdminNameNotCoerced -Value 'ops-admin'
            $out | Should -BeNullOrEmpty
        }
    }

    It 'throws on a stringified object' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbAdminNameNotCoerced -Value '@{admin=; api_token=}' } |
                Should -Throw -ExpectedMessage '*stringified object*'
        }
    }

    It 'names .admin.name as the extraction path in the message' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbAdminNameNotCoerced -Value '@{admin=}' } |
                Should -Throw -ExpectedMessage '*admin.name*'
        }
    }

    It 'checks every element of an array, not just the first' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbAdminNameNotCoerced -Value @('ops-admin', '@{admin=}') } |
                Should -Throw -ExpectedMessage '*stringified object*'
        }
    }

    It 'ignores a non-string value' {
        InModuleScope PureStorageFlashBladePowerShell {
            { Assert-PfbAdminNameNotCoerced -Value ([PSCustomObject]@{ admin = 'x' }) } |
                Should -Not -Throw
        }
    }
}
