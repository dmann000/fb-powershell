#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbSyslogServer - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends uri as a body field' {
            Update-PfbSyslogServer -Name "syslog-prod" -Uri "tcp://newsyslog.example.com:514" `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'syslog-servers' -and
                $QueryParams['names'] -eq 'syslog-prod' -and
                $Body['uri'] -eq 'tcp://newsyslog.example.com:514'
            }
        }

        It 'sends services as a body field' {
            Update-PfbSyslogServer -Name "syslog-prod" -Services 'data-audit','management' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['services']).Count -eq 2 -and
                $Body['services'][0] -eq 'data-audit' -and
                $Body['services'][1] -eq 'management'
            }
        }

        It 'rejects a -Services value outside the enum' {
            { Update-PfbSyslogServer -Name "syslog-prod" -Services 'bogus' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Update-PfbSyslogServer'
        }

        It 'sends an EMPTY array for -Services @() so the list can be cleared' {
            Update-PfbSyslogServer -Name "syslog-prod" -Services @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('services') -and @($Body['services']).Count -eq 0
            }
        }

        It 'builds sources as name-reference objects (constraint 8b, array of references)' {
            Update-PfbSyslogServer -Name "syslog-prod" -Sources 'eth0' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['sources'].Count -eq 1 -and $Body['sources'][0].name -eq 'eth0'
            }
        }

        It 'sends an EMPTY array for -Sources @() so the list can be cleared' {
            Update-PfbSyslogServer -Name "syslog-prod" -Sources @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('sources') -and @($Body['sources']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbSyslogServer -Name "syslog-prod" -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the server by id when -Id is used' {
            Update-PfbSyslogServer -Id "10314f42-020d-7080-8013-000ddt400090" -Uri 'tcp://x:514' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq '10314f42-020d-7080-8013-000ddt400090' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbSyslogServer -Name "syslog-prod" -Attributes @{ uri = "tls://syslog.corp.com:6514" } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['uri'] -eq 'tls://syslog.corp.com:6514'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbSyslogServer -Name "syslog-prod" -Uri 'tcp://x:514' -Attributes @{ uri = 'tcp://y:514' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Uri' }
            @{ Parameter = 'Sources' }
        ) {
            $attrs = (Get-Command Update-PfbSyslogServer).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'puts ValidateSet(data-audit, management) on -Services in that order (constraint 3)' {
            $attr = (Get-Command Update-PfbSyslogServer).Parameters['Services'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $attr.ValidValues | Should -Be @('data-audit', 'management')
        }
    }
}
