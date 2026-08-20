#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArrayPerformance' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'ValidateSet on -Protocol includes exactly all, nfs, smb, http, s3' {
        $command = Get-Command Get-PfbArrayPerformance
        $validateSetAttr = $command.Parameters['Protocol'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSetAttr.ValidValues | Should -Not -BeNullOrEmpty
        ($validateSetAttr.ValidValues | Sort-Object) | Should -Be (@('all', 'http', 'nfs', 's3', 'smb') | Sort-Object)
    }

    It 'accepts -Protocol all (regression: was rejected before the ValidateSet fix) and passes it through' {
        { Get-PfbArrayPerformance -Protocol all -Array $fakeArray } | Should -Not -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq 'arrays/performance' -and $QueryParams['protocol'] -eq 'all'
        }
    }

    It 'still accepts pre-existing value -Protocol nfs unchanged' {
        { Get-PfbArrayPerformance -Protocol nfs -Array $fakeArray } | Should -Not -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq 'arrays/performance' -and $QueryParams['protocol'] -eq 'nfs'
        }
    }

    It 'rejects an invalid -Protocol value with zero API calls' {
        { Get-PfbArrayPerformance -Protocol bogus -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'makes a call with no protocol query param when -Protocol is omitted' {
        Get-PfbArrayPerformance -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq 'arrays/performance' -and -not $QueryParams.ContainsKey('protocol')
        }
    }
}
