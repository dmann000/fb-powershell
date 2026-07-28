#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbObjectStoreVirtualHost - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends hostname and -NewName as body fields (rename exception, not -VirtualHostName)' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -Hostname 's3.myarray.com' -NewName 'renamed-vhost' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'object-store-virtual-hosts' -and
                $QueryParams['names'] -eq 's3.example.com' -and
                $Body['hostname'] -eq 's3.myarray.com' -and
                $Body['name'] -eq 'renamed-vhost'
            }
        }

        It 'builds attached_servers as name-reference objects (constraint 8b, array of references)' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -AttachedServers 'srv-a','srv-b' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['attached_servers'].Count -eq 2 -and
                $Body['attached_servers'][0].name -eq 'srv-a' -and
                $Body['attached_servers'][1].name -eq 'srv-b'
            }
        }

        It 'sends an EMPTY array for -AttachedServers @() so a list can be cleared' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -AttachedServers @() `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('attached_servers') -and
                @($Body['attached_servers']).Count -eq 0
            }
        }

        It 'builds add_attached_servers as name-reference objects' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -AddAttachedServers 'srv-c' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['add_attached_servers'][0].name -eq 'srv-c'
            }
        }

        It 'builds remove_attached_servers as name-reference objects' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -RemoveAttachedServers 'srv-d' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['remove_attached_servers'][0].name -eq 'srv-d'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the virtual host by id when -Id is used' {
            Update-PfbObjectStoreVirtualHost -Id 'vhost-id-1' -Hostname 's3.myarray.com' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'vhost-id-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -Attributes @{ hostname = 'raw.example.com' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['hostname'] -eq 'raw.example.com'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbObjectStoreVirtualHost -Name 's3.example.com' -Hostname 'x.example.com' -Attributes @{ hostname = 'y.example.com' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'AddAttachedServers' }
            @{ Parameter = 'AttachedServers' }
            @{ Parameter = 'Hostname' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'RemoveAttachedServers' }
        ) {
            $attrs = (Get-Command Update-PfbObjectStoreVirtualHost).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbObjectStoreVirtualHost).Parameters.Keys
            foreach ($p in 'AddAttachedServers','AttachedServers','Hostname','NewName','RemoveAttachedServers') {
                $keys | Should -Contain $p
            }
        }

        It 'has no read-only field parameter (constraint 11: id)' {
            $keys = (Get-Command Update-PfbObjectStoreVirtualHost).Parameters.Keys
            $keys | Should -Not -Contain 'IdField'
        }
    }
}
