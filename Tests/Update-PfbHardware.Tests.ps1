#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbHardware - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends identify_enabled as a body field' {
            Update-PfbHardware -Name 'CH1.FB1' -IdentifyEnabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'hardware' -and
                $QueryParams['names'] -eq 'CH1.FB1' -and
                $Body['identify_enabled'] -eq $true
            }
        }

        It 'sends an explicit -IdentifyEnabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbHardware -Name 'CH1.FB1' -IdentifyEnabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('identify_enabled') -and $Body['identify_enabled'] -eq $false
            }
        }

        It 'omits identify_enabled entirely when not supplied' {
            Update-PfbHardware -Name 'CH1.FB1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('identify_enabled')
            }
        }

        It 'targets the component by id when -Id is used' {
            Update-PfbHardware -Id 'hw-1' -IdentifyEnabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'hw-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbHardware -Name 'CH1.FB1' -Attributes @{ identify_enabled = $true } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['identify_enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbHardware -Name 'CH1.FB1' -IdentifyEnabled $true -Attributes @{ identify_enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -IdentifyEnabled (constraint 3, no spec enum)' {
            $attrs = (Get-Command Update-PfbHardware).Parameters['IdentifyEnabled'].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'does not expose any of the 15 read-only fields as parameters (constraint 11)' {
            $keys = (Get-Command Update-PfbHardware).Parameters.Keys
            foreach ($ro in 'DataMac','Details','Index','ManagementMac','Model','PartNumber','SensorReadings','Serial','Slot','Speed','Status','Temperature','Type') {
                $keys | Should -Not -Contain $ro
            }
        }
    }
}
