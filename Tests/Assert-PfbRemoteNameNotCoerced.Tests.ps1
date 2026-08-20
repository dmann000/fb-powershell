#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Assert-PfbRemoteNameNotCoerced success-stream shape (issue #129)' {

    Context 'the helper itself' {

        It 'emits nothing for a valid scalar remote name' {
            InModuleScope PureStorageFlashBladePowerShell {
                $out = @(Assert-PfbRemoteNameNotCoerced -Value 'FB-B')
                $out.Count | Should -Be 0 -Because 'an imperative assertion helper must not write to the success stream'
            }
        }

        It 'emits nothing for a valid collection of remote names' {
            InModuleScope PureStorageFlashBladePowerShell {
                $out = @(Assert-PfbRemoteNameNotCoerced -Value @('FB-B', 'FB-C'))
                $out.Count | Should -Be 0 -Because 'an imperative assertion helper must not write to the success stream'
            }
        }

        It 'still throws on a stringified object' {
            InModuleScope PureStorageFlashBladePowerShell {
                { Assert-PfbRemoteNameNotCoerced -Value '@{id=10314f42-aaaa; status=connected; remote=}' } |
                    Should -Throw -ExpectedMessage '*stringified object*'
            }
        }

        It 'still throws when only a later element of a collection is malformed' {
            InModuleScope PureStorageFlashBladePowerShell {
                { Assert-PfbRemoteNameNotCoerced -Value @('FB-B', '@{id=x}') } |
                    Should -Throw -ExpectedMessage '*stringified object*'
            }
        }
    }

    Context 'public callers with -RemoteName' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
                [PSCustomObject]@{ PfbSentinel = 'api-result' }
            }
        }

        It '<Command> emits only the API result' -ForEach @(
            @{ Command = 'Get-PfbArrayConnection';                          Extra = @{} }
            @{ Command = 'Get-PfbArrayConnectionPath';                      Extra = @{} }
            @{ Command = 'Get-PfbArrayConnectionPerformanceReplication';    Extra = @{} }
            @{ Command = 'Remove-PfbArrayConnection';                       Extra = @{ Confirm = $false } }
        ) {
            $params = $Extra.Clone()
            $params['RemoteName'] = 'FB-B'
            $params['Array'] = $script:fakeArray

            $out = @(& $Command @params)

            $out.Count | Should -Be 1 -Because "$Command must emit the API result and nothing else"
            $out[0].PfbSentinel | Should -BeExactly 'api-result'
            Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly
        }
    }
}
