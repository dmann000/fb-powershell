#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbFileSystemExport - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends export_name as a plain body field' {
            Update-PfbFileSystemExport -Name 'export1' -ExportName '/fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'file-system-exports' -and
                $QueryParams['names'] -eq 'export1' -and
                $Body['export_name'] -eq '/fs1'
            }
        }

        It 'sends an EMPTY string for -ExportName "" rather than dropping the key' {
            Update-PfbFileSystemExport -Name 'export1' -ExportName '' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('export_name') -and $Body['export_name'] -eq ''
            }
        }

        It 'sends member, policy, server, and share_policy as name-reference objects' {
            Update-PfbFileSystemExport -Name 'export1' -Member 'fs1' -Policy 'nfs-default' `
                -Server 'server1' -SharePolicy 'share-default' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['member'].name -eq 'fs1' -and
                $Body['policy'].name -eq 'nfs-default' -and
                $Body['server'].name -eq 'server1' -and
                $Body['share_policy'].name -eq 'share-default'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbFileSystemExport -Name 'export1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the export by id when -Id is used' {
            Update-PfbFileSystemExport -Id 'export-1' -ExportName '/fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'export-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbFileSystemExport -Name 'export1' -Attributes @{ rules = '*(ro)' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['rules'] -eq '*(ro)'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbFileSystemExport -Name 'export1' -ExportName '/fs1' -Attributes @{ export_name = '/fs2' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'read-only fields are not exposed (constraint 11)' {
        It 'has none of the read-only field parameters' -ForEach @(
            @{ Parameter = 'Context' }
            @{ Parameter = 'Enabled' }
            @{ Parameter = 'PolicyType' }
            @{ Parameter = 'Status' }
        ) {
            (Get-Command Update-PfbFileSystemExport).Parameters.Keys | Should -Not -Contain $Parameter
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'ExportName' }
            @{ Parameter = 'Member' }
            @{ Parameter = 'Policy' }
            @{ Parameter = 'Server' }
            @{ Parameter = 'SharePolicy' }
        ) {
            $attrs = (Get-Command Update-PfbFileSystemExport).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbFileSystemExport).Parameters.Keys
            foreach ($p in 'ExportName', 'Member', 'Policy', 'Server', 'SharePolicy') {
                $keys | Should -Contain $p
            }
        }
    }
}
