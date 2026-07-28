#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbObjectStoreRemoteCredential - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends access_key_id and secret_access_key as body fields' {
            Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -AccessKeyId 'AKIAIOSFODNN7EXAMPLE' `
                -SecretAccessKey 'newSecretKeyValue12345EXAMPLEKEY' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'object-store-remote-credentials' -and
                $QueryParams['names'] -eq 's3-repl-cred' -and
                $Body['access_key_id'] -eq 'AKIAIOSFODNN7EXAMPLE' -and
                $Body['secret_access_key'] -eq 'newSecretKeyValue12345EXAMPLEKEY'
            }
        }

        It 'sends an EMPTY string for -AccessKeyId "" rather than dropping the key' {
            Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -AccessKeyId '' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('access_key_id') -and $Body['access_key_id'] -eq ''
            }
        }

        It 'sends -NewName as the name body field (rename exception, not -RemoteCredentialName)' {
            Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -NewName 'renamed-cred' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['name'] -eq 'renamed-cred'
            }
        }

        It 'builds remote as a name-reference object (constraint 8a, scalar reference)' {
            Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -Remote 'target-1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['remote'].name -eq 'target-1'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the remote credential by id when -Id is used' {
            Update-PfbObjectStoreRemoteCredential -Id 'cred-id-1' -AccessKeyId 'x' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'cred-id-1' -and -not $QueryParams.ContainsKey('names')
            }
        }

        It 'has no -SecretAccessKey default value (sensitive field)' {
            (Get-Command Update-PfbObjectStoreRemoteCredential).Parameters['SecretAccessKey'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } |
                Should -BeNullOrEmpty
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -Attributes @{ secret_access_key = 'raw' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['secret_access_key'] -eq 'raw'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbObjectStoreRemoteCredential -Name 's3-repl-cred' -AccessKeyId 'x' -Attributes @{ access_key_id = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'AccessKeyId' }
            @{ Parameter = 'NewName' }
            @{ Parameter = 'Remote' }
            @{ Parameter = 'SecretAccessKey' }
        ) {
            $attrs = (Get-Command Update-PfbObjectStoreRemoteCredential).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbObjectStoreRemoteCredential).Parameters.Keys
            foreach ($p in 'AccessKeyId','NewName','Remote','SecretAccessKey') {
                $keys | Should -Contain $p
            }
        }

        It 'has no read-only field parameters (constraint 11: context, id, realms)' {
            $keys = (Get-Command Update-PfbObjectStoreRemoteCredential).Parameters.Keys
            foreach ($p in 'Context','Realms') {
                $keys | Should -Not -Contain $p
            }
        }
    }
}
