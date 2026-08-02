#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force
}

Describe 'Invoke-PfbApiRequest - HttpTimeoutMs is applied' {
    It 'passes Array.HttpTimeoutMs (converted to whole seconds) as TimeoutSec' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' -and $TimeoutSec -eq 45 }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint      = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken      = $null; AuthMethod = 'ApiToken'
                SkipCertificateCheck = $false; HttpTimeoutMs = 45000
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*file-systems*' -and $TimeoutSec -eq 45
        }
    }

    It 'defaults to 30 seconds when HttpTimeoutMs is absent from the connection object' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' -and $TimeoutSec -eq 30 }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*file-systems*' -and $TimeoutSec -eq 30
        }
    }

    It 'passes TimeoutSec to Connect-PfbArrayInternal on 401 auto-reconnect' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            $mockResponse = @{
                Headers = @{ 'x-auth-token' = 'new-token' }
            }
            return $mockResponse
        } -ParameterFilter { $Uri -like '*login*' -and $TimeoutSec -eq 45 }

        InModuleScope PureStorageFlashBladePowerShell {
            # Test Connect-PfbArrayInternal directly
            $result = Connect-PfbArrayInternal -Endpoint 'fb.test' -ApiToken 'test-token' -ApiVersion '2.26' -TimeoutSec 45
            $result.AuthToken | Should -Be 'new-token'
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*login*' -and $TimeoutSec -eq 45
        }
    }
}

Describe 'Invoke-PfbApiRequest - PUT support' {
    It 'sends Method PUT with a serialised JSON body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*presets/workload*' }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method PUT -Endpoint 'presets/workload' -Body @{ name = 'p1' } | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body -eq '{"name":"p1"}'
        }
    }

    It 'sends no Body key on a PUT with no -Body' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*presets/workload*' }

        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method PUT -Endpoint 'presets/workload' | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $null -eq $Body
        }
    }

    # Guards against widening the :100 body guard too far -- a body handed to a verb that must
    # not carry one should be dropped, exactly as it was before PUT was added.
    It 'still sends no Body on GET or DELETE even when -Body is supplied' -ForEach @(
        @{ Verb = 'GET' }
        @{ Verb = 'DELETE' }
    ) {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ Verb = $Verb } {
            param($Verb)
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method $Verb -Endpoint 'file-systems' -Body @{ name = 'x' } | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $null -eq $Body
        }
    }

    It 'still rejects a verb outside the ValidateSet' {
        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            { Invoke-PfbApiRequest -Array $array -Method 'TRACE' -Endpoint 'file-systems' } |
                Should -Throw
        }
    }
}

Describe 'Invoke-PfbApiRequest - array request bodies' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            [PSCustomObject]@{ items = @() }
        }
    }

    # Key order inside each serialised object is not asserted anywhere below: PowerShell
    # randomises hashtable enumeration order per process, so both orderings are correct.

    It 'serialises an array body as a top-level JSON array' {
        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            $tags = [hashtable[]]@(
                @{ key = 'team'; value = 'analytics' }
                @{ key = 'env'; value = 'prod' }
            )
            Invoke-PfbApiRequest -Array $array -Method PUT -Endpoint 'workloads/tags/batch' -Body $tags | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Body.StartsWith('[') -and $Body.EndsWith(']') -and
            $Body -match '"analytics"' -and $Body -match '"prod"'
        }
    }

    # The single-element case is the one that regresses silently: piping a one-element
    # collection into ConvertTo-Json unrolls it into a bare object.
    It 'keeps a SINGLE-element array body an array rather than collapsing it to an object' {
        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            $tags = [hashtable[]]@(@{ key = 'team'; value = 'analytics' })
            Invoke-PfbApiRequest -Array $array -Method PUT -Endpoint 'workloads/tags/batch' -Body $tags | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Body.StartsWith('[') -and $Body.EndsWith(']') -and $Body -match '"analytics"'
        }
    }

    # Regression gate on the widened -Body: a hashtable must still serialise to a JSON
    # object, unchanged by the move from the pipeline to -InputObject.
    It 'still serialises a hashtable body as a JSON object' {
        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method POST -Endpoint 'buckets' -Body @{ name = 'b1' } | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Body -eq '{"name":"b1"}'
        }
    }

    # -Body was widened from [hashtable] to [System.Collections.ICollection], not to
    # [object]: the shapes [hashtable] rejected must still be rejected at bind time.
    It 'still rejects a non-collection -Body' -ForEach @(
        @{ Label = 'int'; Value = 42 }
        @{ Label = 'string'; Value = 'not-a-body' }
        @{ Label = 'PSCustomObject'; Value = [PSCustomObject]@{ name = 'b1' } }
    ) {
        InModuleScope PureStorageFlashBladePowerShell -Parameters @{ value = $Value } {
            param($value)
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            { Invoke-PfbApiRequest -Array $array -Method POST -Endpoint 'buckets' -Body $value } |
                Should -Throw
        }
    }

    # New-PfbFileSystemSnapshot builds $body = $null and passes it unconditionally, so the
    # widened type must still bind an explicit $null, not only an omitted -Body.
    It 'still accepts an explicit $null -Body and sends no body' {
        InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            $nothing = $null
            Invoke-PfbApiRequest -Array $array -Method POST -Endpoint 'buckets' -Body $nothing | Out-Null
        }

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $null -eq $Body
        }
    }
}

Describe 'Invoke-PfbApiRequest - AutoPaginate honors -Limit' {
    It 'stops paginating and trims results once the running total reaches the requested limit' {
        $script:pageCallCount = 0
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:pageCallCount++
            switch ($script:pageCallCount) {
                1 {
                    [PSCustomObject]@{
                        items              = @(1..6 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                        continuation_token = 'token-page-2'
                    }
                }
                2 {
                    [PSCustomObject]@{
                        items              = @(7..12 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                        continuation_token = 'token-page-3'
                    }
                }
                default {
                    throw "Unexpected extra page request (call #$script:pageCallCount) -- the -Limit guard should have stopped pagination after call #2"
                }
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $script:result = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' -QueryParams @{ limit = 10 } -AutoPaginate
        }

        $script:result.Count | Should -Be 10
        $script:pageCallCount | Should -Be 2
        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $Uri -like '*file-systems*' }
    }

    It 'still auto-paginates the full collection when no -Limit is given' {
        $script:pageCallCount2 = 0
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
            $script:pageCallCount2++
            if ($script:pageCallCount2 -eq 1) {
                [PSCustomObject]@{
                    items              = @(1..6 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                    continuation_token = 'token-page-2'
                }
            }
            else {
                [PSCustomObject]@{
                    items = @(7..9 | ForEach-Object { [PSCustomObject]@{ name = "fs$_" } })
                }
            }
        } -ParameterFilter { $Uri -like '*file-systems*' }

        $script:result2 = InModuleScope PureStorageFlashBladePowerShell {
            $array = [PSCustomObject]@{
                Endpoint = 'fb.test'; ApiVersion = '2.26'; AuthToken = 'tok'
                ApiToken = $null; AuthMethod = 'ApiToken'; SkipCertificateCheck = $false
            }
            Invoke-PfbApiRequest -Array $array -Method GET -Endpoint 'file-systems' -QueryParams @{} -AutoPaginate
        }

        $script:result2.Count | Should -Be 9
        $script:pageCallCount2 | Should -Be 2
    }
}
