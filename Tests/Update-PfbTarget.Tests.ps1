#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbTarget - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends address as a body field' {
            Update-PfbTarget -Name 's3-target-aws' -Address 's3.us-east-1.amazonaws.com' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'targets' -and
                $QueryParams['names'] -eq 's3-target-aws' -and
                $Body['address'] -eq 's3.us-east-1.amazonaws.com'
            }
        }

        It 'sends an EMPTY string for -Address "" rather than dropping the key' {
            Update-PfbTarget -Name 's3-target-aws' -Address '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('address') -and $Body['address'] -eq ''
            }
        }

        It 'builds ca_certificate_group as a name-reference object (constraint 8a)' {
            Update-PfbTarget -Name 's3-target-aws' -CaCertificateGroup 'my-certs' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['ca_certificate_group'].name -eq 'my-certs'
            }
        }

        It 'sends -NewName as the name body field (rename exception)' {
            Update-PfbTarget -Name 's3-target-aws' -NewName 's3-target-renamed' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 's3-target-renamed'
            }
        }

        It 'has no -TargetName-shaped body parameter, only -NewName' {
            (Get-Command Update-PfbTarget).Parameters.Keys | Should -Not -Contain 'TargetName'
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbTarget -Name 's3-target-aws' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the replication target by id when -Id is used' {
            Update-PfbTarget -Id 'target-1' -Address 'new.example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'target-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbTarget -Name 's3-target-aws' -Attributes @{ address = 'raw.example.com' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['address'] -eq 'raw.example.com'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbTarget -Name 's3-target-aws' -Address 'x.example.com' -Attributes @{ address = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Address' }
            @{ Parameter = 'CaCertificateGroup' }
            @{ Parameter = 'NewName' }
        ) {
            $attrs = (Get-Command Update-PfbTarget).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }
    }
}
