#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbWormPolicy - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends an explicit -DefaultRetention 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbWormPolicy -Name 'worm-compliance' -DefaultRetention 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'worm-data-policies' -and
                $QueryParams['names'] -eq 'worm-compliance' -and
                $Body.ContainsKey('default_retention') -and $Body['default_retention'] -eq 0
            }
        }

        It 'sends default_retention as a body field when non-zero' {
            Update-PfbWormPolicy -Name 'worm-compliance' -DefaultRetention 7776000000 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['default_retention'] -eq 7776000000
            }
        }

        It 'sends an explicit -Enabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbWormPolicy -Name 'worm-compliance' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'builds location as a name-reference object' {
            Update-PfbWormPolicy -Name 'worm-compliance' -Location 'array-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['location'].name -eq 'array-1'
            }
        }

        It 'sends an explicit -MaxRetention 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbWormPolicy -Name 'worm-compliance' -MaxRetention 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('max_retention') -and $Body['max_retention'] -eq 0
            }
        }

        It 'sends an explicit -MinRetention 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbWormPolicy -Name 'worm-compliance' -MinRetention 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('min_retention') -and $Body['min_retention'] -eq 0
            }
        }

        It 'sends mode as a body field' {
            Update-PfbWormPolicy -Name 'worm-compliance' -Mode 'regulatory' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['mode'] -eq 'regulatory'
            }
        }

        It 'sends retention_lock as a body field' {
            Update-PfbWormPolicy -Name 'worm-compliance' -RetentionLock 'locked' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['retention_lock'] -eq 'locked'
            }
        }

        It 'rejects an invalid -RetentionLock value via ValidateSet (constraint 3)' {
            { Update-PfbWormPolicy -Name 'worm-compliance' -RetentionLock 'bogus' `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } | Should -Throw
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbWormPolicy -Name 'worm-compliance' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the policy by id when -Id is used' {
            Update-PfbWormPolicy -Id 'policy-1' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'policy-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbWormPolicy -Name 'worm-compliance' -Attributes @{ retention_lock = 'locked' } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['retention_lock'] -eq 'locked'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time (constraint 5: parameter sets, no extra throw)' {
            { Update-PfbWormPolicy -Name 'worm-compliance' -Mode 'regulatory' -Attributes @{ mode = 'regulatory' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are never exposed (constraint 11)' {
        It 'has no -IsLocal, -PolicyType, or -NewName parameter (name is read-only on this endpoint)' {
            $keys = (Get-Command Update-PfbWormPolicy).Parameters.Keys
            $keys | Should -Not -Contain 'IsLocal'
            $keys | Should -Not -Contain 'PolicyType'
            $keys | Should -Not -Contain 'NewName'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'DefaultRetention' }
            @{ Parameter = 'Enabled' }
            @{ Parameter = 'Location' }
            @{ Parameter = 'MaxRetention' }
            @{ Parameter = 'MinRetention' }
            @{ Parameter = 'Mode' }
        ) {
            $attrs = (Get-Command Update-PfbWormPolicy).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'puts exactly the spec ValidateSet on -RetentionLock' {
            $attrs = (Get-Command Update-PfbWormPolicy).Parameters['RetentionLock'].Attributes
            $validateSet = $attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Be @('unlocked', 'locked')
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbWormPolicy).Parameters.Keys
            foreach ($p in 'DefaultRetention','Enabled','Location','MaxRetention','MinRetention','Mode','RetentionLock') {
                $keys | Should -Contain $p
            }
        }
    }
}
