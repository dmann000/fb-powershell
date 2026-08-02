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
