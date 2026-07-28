#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbSnmpManager - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends -SnmpHost as the host body field (naming collision with -Host)' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -SnmpHost '10.21.100.55' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'snmp-managers' -and
                $QueryParams['names'] -eq 'snmp-mgr01' -and
                $Body['host'] -eq '10.21.100.55'
            }
        }

        It 'has no -Host parameter (would collide with the PowerShell common parameter)' {
            (Get-Command Update-PfbSnmpManager).Parameters.Keys | Should -Not -Contain 'Host'
        }

        It 'sends name as a body field via -NewName' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -NewName 'snmp-mgr02' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'snmp-mgr02'
            }
        }

        It 'sends notification as a body field' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -Notification 'trap' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['notification'] -eq 'trap'
            }
        }

        It 'rejects a -Notification value outside the enum' {
            { Update-PfbSnmpManager -Name 'snmp-mgr01' -Notification 'bogus' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Update-PfbSnmpManager'
        }

        It 'sends version as a body field' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -Version 'v3' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['version'] -eq 'v3'
            }
        }

        It 'rejects a -Version value outside the enum' {
            { Update-PfbSnmpManager -Name 'snmp-mgr01' -Version 'v1' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ErrorId 'ParameterArgumentValidationError,Update-PfbSnmpManager'
        }

        It 'passes v2c through as a composite hashtable (constraint 8c)' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -V2c @{ community = 'new-community' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['v2c']['community'] -eq 'new-community'
            }
        }

        It 'passes v3 through as a composite hashtable (constraint 8c)' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -V3 @{ auth_protocol = 'SHA' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['v3']['auth_protocol'] -eq 'SHA'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the manager by id when -Id is used' {
            Update-PfbSnmpManager -Id 'mgr-1' -NewName 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'mgr-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbSnmpManager -Name 'snmp-mgr01' -Attributes @{ host = '10.21.100.55' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['host'] -eq '10.21.100.55'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbSnmpManager -Name 'snmp-mgr01' -SnmpHost '1.2.3.4' -Attributes @{ host = '5.6.7.8' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'SnmpHost' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'V2c' }
            @{ Parameter = 'V3' }
        ) {
            $attrs = (Get-Command Update-PfbSnmpManager).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'puts ValidateSet(inform, trap) on -Notification in that order (constraint 3)' {
            $attr = (Get-Command Update-PfbSnmpManager).Parameters['Notification'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $attr.ValidValues | Should -Be @('inform', 'trap')
        }

        It 'puts ValidateSet(v2c, v3) on -Version in that order (constraint 3)' {
            $attr = (Get-Command Update-PfbSnmpManager).Parameters['Version'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $attr.ValidValues | Should -Be @('v2c', 'v3')
        }

        It 'has no -SnmpManagerName parameter (the "name" body field uses -NewName per the exception)' {
            (Get-Command Update-PfbSnmpManager).Parameters.Keys | Should -Not -Contain 'SnmpManagerName'
        }
    }
}
