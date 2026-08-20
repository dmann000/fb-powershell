#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbSshCaPolicy - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends enabled as a body field (ContainsKey semantics, not truthiness)' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'ssh-certificate-authority-policies' -and
                $QueryParams['names'] -eq 'ssh-ca-prod' -and
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'builds location as a name-reference object' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -Location 'array-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['location'].name -eq 'array-1'
            }
        }

        It 'sends -NewName as the name body field (rename exception, not -SshCaPolicyName)' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -NewName 'ssh-ca-prod-2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'ssh-ca-prod-2'
            }
        }

        It 'builds signing_authority as a name-reference object' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -SigningAuthority 'ca-cert-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['signing_authority'].name -eq 'ca-cert-1'
            }
        }

        It 'sends static_authorized_principals as a plain string array' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -StaticAuthorizedPrincipals 'alice','bob' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['static_authorized_principals']).Count -eq 2 -and
                $Body['static_authorized_principals'][0] -eq 'alice' -and
                $Body['static_authorized_principals'][1] -eq 'bob'
            }
        }

        It 'sends an EMPTY array for -StaticAuthorizedPrincipals @() so a list can be cleared' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -StaticAuthorizedPrincipals @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('static_authorized_principals') -and
                @($Body['static_authorized_principals']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the policy by id when -Id is used' {
            Update-PfbSshCaPolicy -Id 'policy-1' -Enabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'policy-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -Attributes @{ enabled = $true } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['enabled'] -eq $true
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbSshCaPolicy -Name 'ssh-ca-prod' -Enabled $true -Attributes @{ enabled = $false } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are never exposed (constraint 11)' {
        It 'has no -IsLocal or -PolicyType parameter' {
            $keys = (Get-Command Update-PfbSshCaPolicy).Parameters.Keys
            $keys | Should -Not -Contain 'IsLocal'
            $keys | Should -Not -Contain 'PolicyType'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Enabled' }
            @{ Parameter = 'Location' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'SigningAuthority' }
            @{ Parameter = 'StaticAuthorizedPrincipals' }
        ) {
            $attrs = (Get-Command Update-PfbSshCaPolicy).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbSshCaPolicy).Parameters.Keys
            foreach ($p in 'Enabled','Location','NewName','SigningAuthority','StaticAuthorizedPrincipals') {
                $keys | Should -Contain $p
            }
        }
    }
}
