#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Get-PfbArrayConnectionKey - identity selectors and coercion guard (#90)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'declares an -Id parameter' {
        (Get-Command Get-PfbArrayConnectionKey).Parameters.Keys | Should -Contain 'Id'
    }

    It 'declares ValueFromPipelineByPropertyName on -Id' {
        $attrs = (Get-Command Get-PfbArrayConnectionKey).Parameters['Id'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($attrs | Where-Object { $_.ValueFromPipelineByPropertyName }).Count | Should -BeGreaterThan 0
    }

    It 'does not declare ValueFromPipeline on -Id, so an unrelated object cannot coerce into it' {
        $attrs = (Get-Command Get-PfbArrayConnectionKey).Parameters['Id'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($attrs | Where-Object { $_.ValueFromPipeline }).Count | Should -Be 0
    }

    It 'sends ids when -Id is passed explicitly, and no names key' {
        Get-PfbArrayConnectionKey -Id 'conn-1' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Endpoint -eq 'array-connections/connection-key' -and
            $QueryParams['ids'] -eq 'conn-1' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'accumulates multiple -Id values across pipeline items into one comma-joined ids key' {
        [PSCustomObject]@{ id = 'conn-1' }, [PSCustomObject]@{ id = 'conn-2' } |
            Get-PfbArrayConnectionKey -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq 'conn-1,conn-2' -and -not $QueryParams.ContainsKey('names')
        }
    }

    It 'binds a whole piped connection object by id and sends ids, never a stringified names key' {
        # The shape GET /array-connections returns: an id, no name.
        [PSCustomObject]@{
            id                 = '10314f42-020d-7080-8013-000133810cd0'
            status             = 'connected'
            encrypted          = $true
            management_address = '10.0.0.10'
            remote             = [PSCustomObject]@{ id = 'r-1'; name = 'FB-B' }
        } | Get-PfbArrayConnectionKey -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['ids'] -eq '10314f42-020d-7080-8013-000133810cd0' -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'rejects a piped object carrying neither name nor id instead of stringifying it into -Name' {
        # The self-chain shape: connection-key items carry only connection_key/created/expires.
        {
            [PSCustomObject]@{ connection_key = 'abc123'; created = 1; expires = 2 } |
                Get-PfbArrayConnectionKey -Array $fakeArray -ErrorAction Stop
        } | Should -Throw -ExpectedMessage '*stringified object*'
    }

    It 'issues no request at all when the guard trips' {
        try {
            [PSCustomObject]@{ connection_key = 'abc123'; created = 1; expires = 2 } |
                Get-PfbArrayConnectionKey -Array $fakeArray -ErrorAction Stop
        } catch {
            # Expected: the guard throws terminatingly, so the end block never runs.
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'still binds a bare string to -Name by value and sends names' {
        'remote-fb-dc2' | Get-PfbArrayConnectionKey -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'remote-fb-dc2' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'still sends names when -Name is passed explicitly' {
        Get-PfbArrayConnectionKey -Name 'remote-fb-dc2','remote-fb-dc3' -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['names'] -eq 'remote-fb-dc2,remote-fb-dc3' -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'rejects -Name together with -Id at bind time, and makes no API call' {
        # The spec declares ids "cannot be provided together with the `name` or `names` query
        # parameters", so the combination is refused before it reaches the wire.
        { Get-PfbArrayConnectionKey -Name 'remote-fb-dc2' -Id 'conn-1' -Array $fakeArray -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It 'still routes filter/sort/limit through the common helper with no selector key' {
        Get-PfbArrayConnectionKey -Filter "expires>0" -Sort 'created' -Limit 5 -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['filter'] -eq "expires>0" -and $QueryParams['sort'] -eq 'created' -and
            $QueryParams['limit'] -eq 5 -and
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'sends no selector key at all when listing everything' {
        Get-PfbArrayConnectionKey -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            -not $QueryParams.ContainsKey('names') -and -not $QueryParams.ContainsKey('ids')
        }
    }

    It 'documents -Id in comment-based help' {
        $help = Get-Help Get-PfbArrayConnectionKey -Full
        @($help.parameters.parameter | Where-Object { $_.name -eq 'Id' }).Count | Should -Be 1
    }
}
