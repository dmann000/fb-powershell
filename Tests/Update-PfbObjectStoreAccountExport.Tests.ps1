#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbObjectStoreAccountExport - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends an explicit -ExportEnabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbObjectStoreAccountExport -Name 'export-1' -ExportEnabled:$false `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'object-store-account-exports' -and
                $QueryParams['names'] -eq 'export-1' -and
                $Body.ContainsKey('export_enabled') -and $Body['export_enabled'] -eq $false
            }
        }

        It 'omits export_enabled entirely when -ExportEnabled is not supplied' {
            Update-PfbObjectStoreAccountExport -Name 'export-1' -Policy 'export-policy' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('export_enabled')
            }
        }

        It 'builds policy as a name-reference object (constraint 8a, scalar reference)' {
            Update-PfbObjectStoreAccountExport -Name 'export-1' -Policy 'export-policy' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['policy'].name -eq 'export-policy'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbObjectStoreAccountExport -Name 'export-1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the account export by id when -Id is used' {
            Update-PfbObjectStoreAccountExport -Id 'export-id-1' -ExportEnabled:$true `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'export-id-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbObjectStoreAccountExport -Name 'export-1' -Attributes @{ export_enabled = $false } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['export_enabled'] -eq $false
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbObjectStoreAccountExport -Name 'export-1' -ExportEnabled:$false -Attributes @{ export_enabled = $true } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ExportEnabled' }
            @{ Parameter = 'Policy' }
        ) {
            $attrs = (Get-Command Update-PfbObjectStoreAccountExport).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbObjectStoreAccountExport).Parameters.Keys
            foreach ($p in 'ExportEnabled','Policy') {
                $keys | Should -Contain $p
            }
        }
    }
}
