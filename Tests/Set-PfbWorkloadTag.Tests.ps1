#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for Set-PfbWorkloadTag.
.DESCRIPTION
    The cmdlet had no tests. These assert the shape that actually reaches the wire, so they
    survive the cmdlet being refolded onto Invoke-PfbApiRequest: Invoke-RestMethod is the
    mock boundary, not Invoke-PfbApiRequest.
#>

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{
        Endpoint             = 'fb.example.test'
        ApiVersion           = '2.26'
        AuthToken            = 'x'
        ApiToken             = $null
        AuthMethod           = 'ApiToken'
        SkipCertificateCheck = $false
    }
}

Describe 'Set-PfbWorkloadTag - wire body shape' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }
    }

    # The #77 regression. PUT /workloads/tags/batch declares minItems 1 on a top-level array,
    # and [ValidateCount(1, 30)] explicitly permits one tag -- but a one-element collection
    # piped into ConvertTo-Json unrolls and serialises as a bare object, which the array
    # rejects. A two-tag call passes either way, so ONE tag is the assertion that matters.
    #
    # Key order inside each tag object is deliberately not asserted: PowerShell randomises
    # hashtable enumeration order per process, so {"key":..,"value":..} and the reverse are
    # both correct output.
    It 'serialises a SINGLE tag as a one-element JSON array, not a bare object' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Body.Trim().StartsWith('[') -and
            $Body.Trim().EndsWith(']') -and
            $Body -match '"analytics"'
        }
    }

    It 'serialises multiple tags as a JSON array' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(
            @{ key = 'team'; value = 'analytics' }
            @{ key = 'env'; value = 'prod' }
        ) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Body.Trim().StartsWith('[') -and
            $Body -match '"analytics"' -and
            $Body -match '"prod"'
        }
    }

    It 'sends PUT to the workloads/tags/batch endpoint' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -like '*/workloads/tags/batch*'
        }
    }
}

Describe 'Set-PfbWorkloadTag - query parameters reach the wire' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }
    }

    It 'targets by name via resource_names' {
        Set-PfbWorkloadTag -ResourceName 'wl1', 'wl2' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*resource_names=wl1*wl2*' -and $Uri -notlike '*resource_ids*'
        }
    }

    It 'targets by id via resource_ids' {
        Set-PfbWorkloadTag -ResourceId 'wl-1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*resource_ids=wl-1*' -and $Uri -notlike '*resource_names*'
        }
    }
}

Describe 'Set-PfbWorkloadTag - ShouldProcess gates the call' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }
    }

    It 'makes no request under -WhatIf' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -WhatIf -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Set-PfbWorkloadTag - routed through Invoke-PfbApiRequest (#77)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { }
    }

    It 'sends PUT to workloads/tags/batch' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Endpoint -eq 'workloads/tags/batch'
        }
    }

    # The point of the refactor: the hand-rolled call skipped capability gating, error
    # normalisation and Bearer-token auth. If a direct call ever comes back, this says so.
    It 'makes no direct Invoke-RestMethod call' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }

    It 'passes -Tags through as the body, unmodified and still a collection' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(
            @{ key = 'team'; value = 'analytics'; namespace = 'default' }
            @{ key = 'env'; value = 'prod' }
        ) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body.Count -eq 2 -and
            $Body[0]['key'] -eq 'team' -and $Body[0]['namespace'] -eq 'default' -and
            $Body[1]['value'] -eq 'prod'
        }
    }

    # A one-element [hashtable[]] must not be unwrapped into a bare hashtable by parameter
    # binding on the way into the shared path -- that would put the #77 defect back.
    It 'passes a SINGLE tag through as a one-element collection, not a bare hashtable' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $Body -is [array] -and $Body.Count -eq 1 -and $Body[0]['key'] -eq 'team'
        }
    }

    It 'puts the targeting selectors in QueryParams' {
        Set-PfbWorkloadTag -ResourceName 'wl1', 'wl2' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
            $QueryParams['resource_names'] -eq 'wl1,wl2' -and -not $QueryParams.ContainsKey('resource_ids')
        }
    }

    It 'makes no request under -WhatIf' {
        Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -WhatIf -Array $fakeArray

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe 'Set-PfbWorkloadTag - capability gating now applies' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }
    }

    # PUT /workloads/tags/batch is minVersion 2.23 in Data/PfbCapabilityMap.json. Before the
    # refactor the hand-rolled call bypassed Assert-PfbApiCapability entirely and this went
    # out on the wire to be rejected by the array.
    It 'throws locally, with no network call, against an array below the endpoint minVersion' {
        $oldArray = [PSCustomObject]@{
            Endpoint             = 'fb.example.test'
            ApiVersion           = '2.22'
            AuthToken            = 'x'
            ApiToken             = $null
            AuthMethod           = 'ApiToken'
            SkipCertificateCheck = $false
        }

        { Set-PfbWorkloadTag -ResourceName 'wl1' -Tags @(@{ key = 'team'; value = 'analytics' }) -Confirm:$false -Array $oldArray } |
            Should -Throw -ExpectedMessage '*PUT /workloads/tags/batch requires REST 2.23*'

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }
}
