#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{
        Endpoint   = 'fb.example.test'
        ApiVersion = '2.0'
        AuthToken  = 'x'
    }
}

Describe 'Issue #90 dead selector removal' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    # ------------------------------------------------------------------
    # Get-PfbOpenFile -- GET /file-systems/open-files declares
    # ids/limit/continuation_token and friends, but NOT names.
    # ------------------------------------------------------------------
    Context 'Get-PfbOpenFile' {
        It 'no longer declares a Name parameter' {
            (Get-Command Get-PfbOpenFile).Parameters.Keys | Should -Not -Contain 'Name'
        }

        It 'rejects -Name at bind time' {
            { Get-PfbOpenFile -Name 'fs01' -Array $script:fakeArray } | Should -Throw
        }

        It 'leaves no ByName parameter set behind' {
            (Get-Command Get-PfbOpenFile).ParameterSets.Name | Should -Not -Contain 'ByName'
        }

        It 'still declares Id as a string array' {
            $idParam = (Get-Command Get-PfbOpenFile).Parameters['Id']
            $idParam | Should -Not -BeNullOrEmpty
            $idParam.ParameterType.FullName | Should -Be 'System.String[]'
        }

        It 'declares ValueFromPipelineByPropertyName on Id, and not bare ValueFromPipeline' {
            $paramAttrs = @((Get-Command Get-PfbOpenFile).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($paramAttrs | ForEach-Object { $_.ValueFromPipelineByPropertyName }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipeline }) | Should -Not -Contain $true
        }

        It 'binds Id from a piped wire item by property name' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedMethod = 'GET'
            $expectedIds = 'id-1'

            [PSCustomObject]@{ id = 'id-1' } | Get-PfbOpenFile -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'accumulates ids across several piped wire items into one request' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedIds = 'id-1,id-2'

            @([PSCustomObject]@{ id = 'id-1' }, [PSCustomObject]@{ id = 'id-2' }) |
                Get-PfbOpenFile -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['ids'] -eq $expectedIds
            }
        }

        It 'refuses a bare piped string rather than coercing it into ids' {
            { 'id-1' | Get-PfbOpenFile -Array $script:fakeArray -ErrorAction Stop } | Should -Throw
        }

        It 'emits exactly ids for -Id on GET file-systems/open-files' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedMethod = 'GET'
            $expectedIds = 'id-1,id-2'

            Get-PfbOpenFile -Id 'id-1', 'id-2' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams.ContainsKey('ids') -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'emits no query keys at all for a bare read' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedMethod = 'GET'

            Get-PfbOpenFile -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 0
            }
        }
    }

    # ------------------------------------------------------------------
    # Remove-PfbOpenFile -- DELETE /file-systems/open-files declares
    # ids ONLY.
    # ------------------------------------------------------------------
    Context 'Remove-PfbOpenFile' {
        It 'no longer declares a Name parameter' {
            (Get-Command Remove-PfbOpenFile).Parameters.Keys | Should -Not -Contain 'Name'
        }

        It 'rejects -Name at bind time' {
            { Remove-PfbOpenFile -Name 'fs01' -Array $script:fakeArray -Confirm:$false } | Should -Throw
        }

        It 'leaves no ByName parameter set behind' {
            (Get-Command Remove-PfbOpenFile).ParameterSets.Name | Should -Not -Contain 'ByName'
        }

        It 'keeps Id mandatory' {
            $idParam = (Get-Command Remove-PfbOpenFile).Parameters['Id']
            $idParam | Should -Not -BeNullOrEmpty
            $mandatory = @($idParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory })
            $mandatory | Should -Contain $true
        }

        # NOTE: no bare-piped-string case here. Id is Mandatory on this cmdlet, so an
        # unbindable pipeline object can drop into the interactive "Supply values for
        # parameters" prompt and hang a non-interactive run. The absence of bare
        # ValueFromPipeline is asserted from the attribute metadata instead, which is
        # the same guarantee without the hang risk.
        It 'declares ValueFromPipelineByPropertyName on Id, and not bare ValueFromPipeline' {
            $paramAttrs = @((Get-Command Remove-PfbOpenFile).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($paramAttrs | ForEach-Object { $_.ValueFromPipelineByPropertyName }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipeline }) | Should -Not -Contain $true
        }

        It 'declares bare ValueFromPipeline on NO parameter at all' {
            # Broader than the Id-scoped assertion above: the no-bare-pipeline guarantee
            # covers the cmdlet's whole surface, so a future parameter cannot reintroduce
            # bare ValueFromPipeline and slip past a check that only looks at Id.
            $piped = @((Get-Command Remove-PfbOpenFile).Parameters.Values |
                ForEach-Object { $_.Attributes } |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline })
            $piped.Count | Should -Be 0
        }

        It 'binds Id from a piped wire item by property name' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedMethod = 'DELETE'
            $expectedIds = 'id-1'

            [PSCustomObject]@{ id = 'id-1' } | Remove-PfbOpenFile -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'issues one DELETE per piped wire item' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedFirst = 'id-1'
            $expectedSecond = 'id-2'

            @([PSCustomObject]@{ id = 'id-1' }, [PSCustomObject]@{ id = 'id-2' }) |
                Remove-PfbOpenFile -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 2 -Exactly
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and $QueryParams.Count -eq 1 -and $QueryParams['ids'] -eq $expectedFirst
            }
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and $QueryParams.Count -eq 1 -and $QueryParams['ids'] -eq $expectedSecond
            }
        }

        It 'emits exactly ids for -Id on DELETE file-systems/open-files' {
            $expectedEndpoint = 'file-systems/open-files'
            $expectedMethod = 'DELETE'
            $expectedIds = 'id-1'

            Remove-PfbOpenFile -Id 'id-1' -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams.ContainsKey('ids') -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }
    }

    # ------------------------------------------------------------------
    # Get-PfbResourceAccess -- GET /resource-accesses declares
    # continuation_token/filter/ids/limit/offset/sort, but NOT names.
    # ------------------------------------------------------------------
    Context 'Get-PfbResourceAccess' {
        It 'no longer declares a Name parameter' {
            (Get-Command Get-PfbResourceAccess).Parameters.Keys | Should -Not -Contain 'Name'
        }

        It 'rejects -Name at bind time' {
            { Get-PfbResourceAccess -Name 'access-prod' -Array $script:fakeArray } | Should -Throw
        }

        It 'leaves no ByName parameter set behind' {
            (Get-Command Get-PfbResourceAccess).ParameterSets.Name | Should -Not -Contain 'ByName'
        }

        It 'still declares Id as a string array' {
            $idParam = (Get-Command Get-PfbResourceAccess).Parameters['Id']
            $idParam | Should -Not -BeNullOrEmpty
            $idParam.ParameterType.FullName | Should -Be 'System.String[]'
        }

        It 'declares ValueFromPipelineByPropertyName on Id, and not bare ValueFromPipeline' {
            $paramAttrs = @((Get-Command Get-PfbResourceAccess).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($paramAttrs | ForEach-Object { $_.ValueFromPipelineByPropertyName }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipeline }) | Should -Not -Contain $true
        }

        It 'binds Id from a piped wire item by property name' {
            $expectedEndpoint = 'resource-accesses'
            $expectedMethod = 'GET'
            $expectedIds = 'id-1'

            [PSCustomObject]@{ id = 'id-1' } | Get-PfbResourceAccess -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'accumulates ids across several piped wire items into one request' {
            $expectedEndpoint = 'resource-accesses'
            $expectedIds = 'id-1,id-2'

            @([PSCustomObject]@{ id = 'id-1' }, [PSCustomObject]@{ id = 'id-2' }) |
                Get-PfbResourceAccess -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['ids'] -eq $expectedIds
            }
        }

        It 'refuses a bare piped string rather than coercing it into ids' {
            { 'id-1' | Get-PfbResourceAccess -Array $script:fakeArray -ErrorAction Stop } | Should -Throw
        }

        It 'emits exactly ids for -Id on GET resource-accesses' {
            $expectedEndpoint = 'resource-accesses'
            $expectedMethod = 'GET'
            $expectedIds = 'id-1,id-2'

            Get-PfbResourceAccess -Id 'id-1', 'id-2' -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams.ContainsKey('ids') -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'still emits the declared filter/sort/limit keys and nothing else' {
            $expectedEndpoint = 'resource-accesses'
            $expectedMethod = 'GET'
            $expectedFilter = "resource_type='file-system'"
            $expectedSort = 'name'
            $expectedLimit = 20

            Get-PfbResourceAccess -Filter $expectedFilter -Sort $expectedSort -Limit $expectedLimit -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 3 -and
                $QueryParams['filter'] -eq $expectedFilter -and
                $QueryParams['sort'] -eq $expectedSort -and
                $QueryParams['limit'] -eq $expectedLimit -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'emits no query keys at all for a bare read' {
            $expectedEndpoint = 'resource-accesses'
            $expectedMethod = 'GET'

            Get-PfbResourceAccess -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 0
            }
        }
    }

    # ------------------------------------------------------------------
    # Remove-PfbResourceAccess -- DELETE /resource-accesses declares
    # ids ONLY.
    # ------------------------------------------------------------------
    Context 'Remove-PfbResourceAccess' {
        It 'no longer declares a Name parameter' {
            (Get-Command Remove-PfbResourceAccess).Parameters.Keys | Should -Not -Contain 'Name'
        }

        It 'rejects -Name at bind time' {
            { Remove-PfbResourceAccess -Name 'access-old' -Array $script:fakeArray -Confirm:$false } | Should -Throw
        }

        It 'leaves no ByName parameter set behind' {
            (Get-Command Remove-PfbResourceAccess).ParameterSets.Name | Should -Not -Contain 'ByName'
        }

        It 'keeps Id mandatory' {
            $idParam = (Get-Command Remove-PfbResourceAccess).Parameters['Id']
            $idParam | Should -Not -BeNullOrEmpty
            $mandatory = @($idParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory })
            $mandatory | Should -Contain $true
        }

        # NOTE: no bare-piped-string case here, for the same mandatory-parameter
        # prompt-hang reason documented on Remove-PfbOpenFile above.
        It 'declares ValueFromPipelineByPropertyName on Id, and not bare ValueFromPipeline' {
            $paramAttrs = @((Get-Command Remove-PfbResourceAccess).Parameters['Id'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($paramAttrs | ForEach-Object { $_.ValueFromPipelineByPropertyName }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipeline }) | Should -Not -Contain $true
        }

        It 'declares bare ValueFromPipeline on NO parameter at all' {
            # Broader than the Id-scoped assertion above: the no-bare-pipeline guarantee
            # covers the cmdlet's whole surface, so a future parameter cannot reintroduce
            # bare ValueFromPipeline and slip past a check that only looks at Id.
            $piped = @((Get-Command Remove-PfbResourceAccess).Parameters.Values |
                ForEach-Object { $_.Attributes } |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline })
            $piped.Count | Should -Be 0
        }

        It 'binds Id from a piped wire item by property name' {
            $expectedEndpoint = 'resource-accesses'
            $expectedMethod = 'DELETE'
            $expectedIds = 'id-1'

            [PSCustomObject]@{ id = 'id-1' } | Remove-PfbResourceAccess -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'issues one DELETE per piped wire item' {
            $expectedEndpoint = 'resource-accesses'
            $expectedFirst = 'id-1'
            $expectedSecond = 'id-2'

            @([PSCustomObject]@{ id = 'id-1' }, [PSCustomObject]@{ id = 'id-2' }) |
                Remove-PfbResourceAccess -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 2 -Exactly
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and $QueryParams.Count -eq 1 -and $QueryParams['ids'] -eq $expectedFirst
            }
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and $QueryParams.Count -eq 1 -and $QueryParams['ids'] -eq $expectedSecond
            }
        }

        It 'emits exactly ids for -Id on DELETE resource-accesses' {
            $expectedEndpoint = 'resource-accesses'
            $expectedMethod = 'DELETE'
            $expectedIds = 'id-1'

            Remove-PfbResourceAccess -Id 'id-1' -Array $script:fakeArray -Confirm:$false

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams.ContainsKey('ids') -and
                $QueryParams['ids'] -eq $expectedIds -and
                -not $QueryParams.ContainsKey('names')
            }
        }
    }

    # ------------------------------------------------------------------
    # Get-PfbFleetKey -- GET /fleets/fleet-key declares
    # continuation_token/filter/limit/offset/sort/total_only, but no
    # names and no ids. It is an unfiltered read plus filter/sort/limit.
    # ------------------------------------------------------------------
    Context 'Get-PfbFleetKey' {
        It 'no longer declares a Name parameter' {
            (Get-Command Get-PfbFleetKey).Parameters.Keys | Should -Not -Contain 'Name'
        }

        It 'rejects -Name at bind time' {
            { Get-PfbFleetKey -Name 'fleet-prod' -Array $script:fakeArray } | Should -Throw
        }

        It 'emits no query keys at all for a bare read' {
            $expectedEndpoint = 'fleets/fleet-key'
            $expectedMethod = 'GET'

            Get-PfbFleetKey -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 0 -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'still emits the declared filter/sort/limit keys and nothing else' {
            $expectedEndpoint = 'fleets/fleet-key'
            $expectedMethod = 'GET'
            $expectedFilter = "name='fleet*'"
            $expectedSort = 'name'
            $expectedLimit = 5

            Get-PfbFleetKey -Filter $expectedFilter -Sort $expectedSort -Limit $expectedLimit -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 3 -and
                $QueryParams['filter'] -eq $expectedFilter -and
                $QueryParams['sort'] -eq $expectedSort -and
                $QueryParams['limit'] -eq $expectedLimit -and
                -not $QueryParams.ContainsKey('names')
            }
        }
    }

    # ------------------------------------------------------------------
    # Get-PfbNetworkConnectionStatistics -- GET
    # /network-interfaces/network-connection-statistics declares
    # current_state/filter/limit/local_host/local_port/offset/
    # remote_host/remote_port/sort, but NOT names.
    # ------------------------------------------------------------------
    Context 'Get-PfbNetworkConnectionStatistics' {
        It 'no longer declares a Name parameter' {
            (Get-Command Get-PfbNetworkConnectionStatistics).Parameters.Keys | Should -Not -Contain 'Name'
        }

        It 'rejects -Name at bind time' {
            { Get-PfbNetworkConnectionStatistics -Name 'vip1' -Array $script:fakeArray } | Should -Throw
        }

        It 'emits no query keys at all for a bare read' {
            $expectedEndpoint = 'network-interfaces/network-connection-statistics'
            $expectedMethod = 'GET'

            Get-PfbNetworkConnectionStatistics -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 0 -and
                -not $QueryParams.ContainsKey('names')
            }
        }

        It 'still emits the declared filter/sort/limit keys and nothing else' {
            $expectedEndpoint = 'network-interfaces/network-connection-statistics'
            $expectedMethod = 'GET'
            $expectedFilter = "interface_type='vip'"
            $expectedSort = 'name'
            $expectedLimit = 10

            Get-PfbNetworkConnectionStatistics -Filter $expectedFilter -Sort $expectedSort -Limit $expectedLimit -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 3 -and
                $QueryParams['filter'] -eq $expectedFilter -and
                $QueryParams['sort'] -eq $expectedSort -and
                $QueryParams['limit'] -eq $expectedLimit -and
                -not $QueryParams.ContainsKey('names')
            }
        }
    }

    # ------------------------------------------------------------------
    # Get-PfbObjectStoreTrustPolicyRule -- GET
    # /object-store-roles/object-store-trust-policies/rules declares
    # names/policy_names/role_ids/role_names/indices/filter/sort/limit/
    # offset/allow_errors/context_names/continuation_token -- but NOT
    # policy_ids. Only PolicyId goes; PolicyName must survive intact.
    # ------------------------------------------------------------------
    Context 'Get-PfbObjectStoreTrustPolicyRule' {
        It 'no longer declares a PolicyId parameter' {
            (Get-Command Get-PfbObjectStoreTrustPolicyRule).Parameters.Keys | Should -Not -Contain 'PolicyId'
        }

        It 'rejects -PolicyId at bind time' {
            { Get-PfbObjectStoreTrustPolicyRule -PolicyId 'pid-1' -Array $script:fakeArray } | Should -Throw
        }

        It 'leaves no ByPolicyId parameter set behind' {
            (Get-Command Get-PfbObjectStoreTrustPolicyRule).ParameterSets.Name | Should -Not -Contain 'ByPolicyId'
        }

        It 'keeps ByPolicyName as the default parameter set' {
            $defaultSet = @((Get-Command Get-PfbObjectStoreTrustPolicyRule).ParameterSets |
                Where-Object { $_.IsDefault } | ForEach-Object { $_.Name })
            $defaultSet | Should -Be 'ByPolicyName'
        }

        It 'keeps PolicyName with its pipeline attributes and alias' {
            $policyNameParam = (Get-Command Get-PfbObjectStoreTrustPolicyRule).Parameters['PolicyName']
            $policyNameParam | Should -Not -BeNullOrEmpty
            $policyNameParam.ParameterType.FullName | Should -Be 'System.String[]'
            $policyNameParam.Aliases | Should -Contain 'policy_name'

            $paramAttrs = @($policyNameParam.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($paramAttrs | ForEach-Object { $_.Mandatory }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipeline }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.ValueFromPipelineByPropertyName }) | Should -Contain $true
            @($paramAttrs | ForEach-Object { $_.Position }) | Should -Contain 0
            @($paramAttrs | ForEach-Object { $_.ParameterSetName }) | Should -Contain 'ByPolicyName'
        }

        It 'emits exactly policy_names for -PolicyName' {
            $expectedEndpoint = 'object-store-roles/object-store-trust-policies/rules'
            $expectedMethod = 'GET'
            $expectedPolicyNames = 's3-admin-role/trust-policy'

            Get-PfbObjectStoreTrustPolicyRule -PolicyName $expectedPolicyNames -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams.ContainsKey('policy_names') -and
                $QueryParams['policy_names'] -eq $expectedPolicyNames -and
                -not $QueryParams.ContainsKey('policy_ids')
            }
        }

        It 'binds PolicyName from the pipeline by property name' {
            $expectedEndpoint = 'object-store-roles/object-store-trust-policies/rules'
            $expectedPolicyNames = 's3-admin-role/trust-policy'

            [PSCustomObject]@{ PolicyName = $expectedPolicyNames } |
                Get-PfbObjectStoreTrustPolicyRule -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams['policy_names'] -eq $expectedPolicyNames -and
                -not $QueryParams.ContainsKey('policy_ids')
            }
        }

        It 'emits exactly names for -Name' {
            $expectedEndpoint = 'object-store-roles/object-store-trust-policies/rules'
            $expectedMethod = 'GET'
            $expectedNames = 's3-admin-role/trust-policy/rule1'

            Get-PfbObjectStoreTrustPolicyRule -Name $expectedNames -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq $expectedMethod -and
                $Endpoint -eq $expectedEndpoint -and
                $QueryParams.Count -eq 1 -and
                $QueryParams.ContainsKey('names') -and
                $QueryParams['names'] -eq $expectedNames -and
                -not $QueryParams.ContainsKey('policy_ids')
            }
        }
    }
}
