#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbAsyncLog - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends end_time and start_time as body fields' {
            Update-PfbAsyncLog -StartTime 1700000000000 -EndTime 1700003600000 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'logs-async' -and
                $Body['start_time'] -eq 1700000000000 -and
                $Body['end_time'] -eq 1700003600000
            }
        }

        It 'sends an explicit -StartTime 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbAsyncLog -StartTime 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('start_time') -and $Body['start_time'] -eq 0
            }
        }

        It 'sends an explicit -EndTime 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbAsyncLog -EndTime 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('end_time') -and $Body['end_time'] -eq 0
            }
        }

        It 'builds hardware_components as name-reference objects' {
            Update-PfbAsyncLog -HardwareComponents 'CH1.FB1','CH1.FB2' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['hardware_components'].Count -eq 2 -and
                $Body['hardware_components'][0].name -eq 'CH1.FB1' -and
                $Body['hardware_components'][1].name -eq 'CH1.FB2'
            }
        }

        It 'sends an EMPTY array for -HardwareComponents @() so the list can be cleared' {
            Update-PfbAsyncLog -HardwareComponents @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('hardware_components') -and
                @($Body['hardware_components']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbAsyncLog -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbAsyncLog -Attributes @{ start_time = 1700000000000 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['start_time'] -eq 1700000000000
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbAsyncLog -StartTime 1 -Attributes @{ start_time = 2 } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'EndTime' }
            @{ Parameter = 'StartTime' }
            @{ Parameter = 'HardwareComponents' }
        ) {
            $attrs = (Get-Command Update-PfbAsyncLog).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'does not expose any of the 6 read-only fields as parameters (constraint 11)' {
            $keys = (Get-Command Update-PfbAsyncLog).Parameters.Keys
            # All six are readOnly on LogsAsync in every cached spec version (verified 2.9 and
            # 2.26): available_files, id, last_request_time, name, processing, progress. Id and
            # Name were previously omitted from this loop only because they were parameters;
            # issue #64 removed them, so the loop can now cover the full read-only set.
            foreach ($ro in 'AvailableFiles','Id','LastRequestTime','Name','Processing','Progress') {
                $keys | Should -Not -Contain $ro
            }
        }
    }

    Context 'issue #64 -- the endpoint takes no query parameters' {
        It 'sends no query parameters at all' {
            Update-PfbAsyncLog -StartTime 1700000000000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'logs-async' -and
                ($null -eq $QueryParams -or $QueryParams.Count -eq 0)
            }
        }

        It 'exposes neither -Name nor -Id, which had no endpoint support to bind to' {
            $keys = (Get-Command Update-PfbAsyncLog).Parameters.Keys
            $keys | Should -Not -Contain 'Name'
            $keys | Should -Not -Contain 'Id'
        }

        It 'collapses to exactly two parameter sets' {
            (Get-Command Update-PfbAsyncLog).ParameterSets.Name | Sort-Object |
                Should -Be @('Attributes', 'Individual')
        }
    }
}
