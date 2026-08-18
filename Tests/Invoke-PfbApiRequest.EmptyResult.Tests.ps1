#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Issue #121. An empty list result used to come back as a one-element
# [PSCustomObject]@{ total_item_count = N } wrapper: truthy, counted as 1 by Measure-Object,
# and -- carrying neither `name` nor `id` -- coerced on the pipeline into
# `names=@{total_item_count=0}`. At least one endpoint ignores that selector and returns its
# entire collection, so a caller who searched, found nothing, and piped the nothing onward
# received everything.
#
# The wrapper is still correct for one caller: a -TotalOnly read, whose whole purpose is the
# count. The array cannot tell the two apart for us. Measured against FB-A at REST 2.26,
# `GET /file-systems?total_only=true` and `GET /file-systems?filter=<no-match>` return the same
# four keys and differ only in the value of `total_item_count`:
#
#   total_only=true    -> { total, continuation_token, total_item_count: 2, items: [] }
#   filter=<no-match>  -> { total, continuation_token, total_item_count: 0, items: [] }
#
# So the discriminator has to be the REQUEST, and it is already in hand: `total_only` in
# $QueryParams, put there by Add-PfbCommonQueryParams. These tests pin both halves -- the
# wrapper survives for a total-only read, and nothing else ever sees it.

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PfbApiRequest - empty results' {

    BeforeEach {
        # The shape the array actually returns for a filter that matches nothing.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{
                total              = $null
                continuation_token = $null
                total_item_count   = 0
                items              = @()
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }
    }

    It 'returns nothing at all when the result is empty' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ filter = "name='zzz-no-such-filesystem'" }
        }

        # Measure-Object, not .Count: @($null).Count is 1, so .Count cannot tell an empty
        # result from a one-element wrapper.
        ($result | Measure-Object).Count | Should -Be 0
    }

    It 'returns a falsy value on an empty result, so "if (Get-PfbX ...)" does not fire' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ filter = "name='zzz-no-such-filesystem'" }
        }

        [bool]$result | Should -BeFalse
    }

    It 'emits no object carrying total_item_count, so nothing can coerce into a selector' {
        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ filter = "name='zzz-no-such-filesystem'" }
        }

        # This is the defect's actual harm: an object whose only property is total_item_count
        # binds ByValue to a -Name parameter as the string '@{total_item_count=0}'.
        @($result | ForEach-Object { $_.PSObject.Properties.Name }) | Should -Not -Contain 'total_item_count'
    }

    It 'iterates zero times when piped into ForEach-Object' {
        $seen = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ filter = "name='zzz-no-such-filesystem'" }
        } | ForEach-Object { 'iteration' }

        ($seen | Measure-Object).Count | Should -Be 0
    }

    It 'suppresses the wrapper even when the array reports a non-zero total against zero items' {
        # Gating must key off the REQUEST, never off the count. A non-zero total_item_count
        # beside an empty items array is exactly what a total-only response looks like, so a
        # count-based guard would leak the wrapper right back to an ordinary caller.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{
                total_item_count = 7
                items            = @()
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems'
        }

        ($result | Measure-Object).Count | Should -Be 0
    }

    It 'returns nothing when no QueryParams were supplied at all' {
        # The guard has to survive a $null $QueryParams -- most read cmdlets pass one, but
        # indexing a $null hashtable is a StrictMode error, not a $null.
        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems'
        }

        ($result | Measure-Object).Count | Should -Be 0
    }

    It 'returns nothing when auto-pagination collects no items across pages' {
        $script:emptyPageCount = 0
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:emptyPageCount++
            if ($script:emptyPageCount -eq 1) {
                [PSCustomObject]@{ items = @(); total_item_count = 0; continuation_token = 'tok2' }
            }
            else {
                [PSCustomObject]@{ items = @(); total_item_count = 0; continuation_token = $null }
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' -QueryParams @{} -AutoPaginate
        }

        ($result | Measure-Object).Count | Should -Be 0
        $script:emptyPageCount | Should -Be 2
    }
}

Describe 'Invoke-PfbApiRequest - total_only reads keep their count' {

    It 'still returns the bare total_item_count object when total_only was requested' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{
                total              = $null
                continuation_token = $null
                total_item_count   = 2
                items              = @()
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ total_only = 'true' }
        }

        ($result | Measure-Object).Count | Should -Be 1
        $result.total_item_count | Should -Be 2
    }

    It 'returns a zero count for a total_only read that matched nothing' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ total_item_count = 0; items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ total_only = 'true'; filter = "name='zzz-no-such-filesystem'" }
        }

        ($result | Measure-Object).Count | Should -Be 1
        $result.total_item_count | Should -Be 0
    }

    It 'does not treat a total_only value other than true as a total-only read' {
        # Add-PfbCommonQueryParams only ever writes the string 'true', so anything else did not
        # come from -TotalOnly. Keying off the value rather than the key also means this code
        # will not inherit that helper's separate ContainsKey defect if it is fixed later.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ total_item_count = 4; items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ total_only = 'false' }
        }

        ($result | Measure-Object).Count | Should -Be 0
    }
}

Describe 'Invoke-PfbApiRequest - unaffected return paths' {

    It 'still returns the items of a non-empty result unchanged' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{
                total_item_count = 2
                items            = @(
                    [PSCustomObject]@{ name = 'fs1' }
                    [PSCustomObject]@{ name = 'fs2' }
                )
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' -QueryParams @{}
        }

        ($result | Measure-Object).Count | Should -Be 2
        @($result)[0].name | Should -Be 'fs1'
    }

    It 'treats a no-items total_item_count-only body as an ordinary empty list' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ total_item_count = 0 }
        } -ParameterFilter { $Uri -like '*file-systems/open-files*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems/open-files' `
                -QueryParams @{}
        }

        ($result | Measure-Object).Count | Should -Be 0
    }

    It 'keeps a no-items total_item_count-only body when total_only was requested' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ total_item_count = 0 }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' `
                -QueryParams @{ total_only = 'true' }
        }

        ($result | Measure-Object).Count | Should -Be 1
        $result.total_item_count | Should -Be 0
    }

    It 'still returns a genuine direct-data body with no items or total_item_count key verbatim' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ version = '2.26' }
        } -ParameterFilter { $Uri -like '*arrays*' }

        $result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'arrays' -QueryParams @{}
        }

        $result.version | Should -Be '2.26'
    }
}
