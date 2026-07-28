#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbStorageClassTieringPolicy - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends archival_rules as a composite hashtable array, passed straight through' {
            $rules = @(@{ after = 86400000 })
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -ArchivalRules $rules -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'storage-class-tiering-policies' -and
                $QueryParams['names'] -eq 'tier-to-archive' -and
                @($Body['archival_rules']).Count -eq 1 -and
                $Body['archival_rules'][0].after -eq 86400000
            }
        }

        It 'sends an EMPTY array for -ArchivalRules @() so the list can be cleared, not omit the key' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -ArchivalRules @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('archival_rules') -and @($Body['archival_rules']).Count -eq 0
            }
        }

        It 'sends enabled as a body field (ContainsKey semantics, not truthiness)' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'builds location as a name-reference object' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -Location 'array-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['location'].name -eq 'array-1'
            }
        }

        It 'sends -NewName as the name body field (rename exception, not -StorageClassTieringPolicyName)' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -NewName 'tier-to-glacier' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'tier-to-glacier'
            }
        }

        It 'sends retrieval_rules as a composite hashtable array, passed straight through' {
            $rules = @(@{ priority = 'standard' })
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -RetrievalRules $rules -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['retrieval_rules']).Count -eq 1 -and
                $Body['retrieval_rules'][0].priority -eq 'standard'
            }
        }

        It 'sends an EMPTY array for -RetrievalRules @() so the list can be cleared, not omit the key' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -RetrievalRules @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('retrieval_rules') -and @($Body['retrieval_rules']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the policy by id when -Id is used' {
            Update-PfbStorageClassTieringPolicy -Id 'policy-1' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'policy-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -Attributes @{ enabled = $true } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbStorageClassTieringPolicy -Name 'tier-to-archive' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are never exposed (constraint 11)' {
        It 'has no -IsLocal or -PolicyType parameter' {
            $keys = (Get-Command Update-PfbStorageClassTieringPolicy).Parameters.Keys
            $keys | Should -Not -Contain 'IsLocal'
            $keys | Should -Not -Contain 'PolicyType'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ArchivalRules' }
            @{ Parameter = 'Enabled' }
            @{ Parameter = 'Location' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'RetrievalRules' }
        ) {
            $attrs = (Get-Command Update-PfbStorageClassTieringPolicy).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbStorageClassTieringPolicy).Parameters.Keys
            foreach ($p in 'ArchivalRules','Enabled','Location','NewName','RetrievalRules') {
                $keys | Should -Contain $p
            }
        }
    }
}
