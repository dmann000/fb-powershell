#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbBucketAuditFilter - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends actions and s3_prefixes as body fields' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -Actions 's3:GetObject', 's3:PutObject' `
                -S3Prefixes 'prefix1', 'prefix2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'buckets/audit-filters' -and
                @($Body['actions']).Count -eq 2 -and $Body['actions'][0] -eq 's3:GetObject' -and
                @($Body['s3_prefixes']).Count -eq 2 -and $Body['s3_prefixes'][1] -eq 'prefix2'
            }
        }

        It 'sends an EMPTY array for -Actions @() so a list can be cleared (constraint 2, array field)' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -Actions @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('actions') -and @($Body['actions']).Count -eq 0
            }
        }

        It 'sends an EMPTY array for -S3Prefixes @() so a list can be cleared (constraint 2, array field)' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -S3Prefixes @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('s3_prefixes') -and @($Body['s3_prefixes']).Count -eq 0
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }

    Context 'query parameters (wire-correctness fix: bucket_names/bucket_ids, not member_names/member_ids)' {
        It 'sends -BucketName as bucket_names, NOT member_names' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['bucket_names'] -eq 'mybucket' -and -not $QueryParams.ContainsKey('member_names')
            }
        }

        It 'sends -BucketId as bucket_ids, NOT member_ids' {
            Update-PfbBucketAuditFilter -BucketId 'bucket-1' -Name 'mybucket' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['bucket_ids'] -eq 'bucket-1' -and -not $QueryParams.ContainsKey('member_ids') -and
                -not $QueryParams.ContainsKey('bucket_names')
            }
        }

        It 'throws when -BucketId is used alone: the required "names" query parameter cannot be inferred from an ID (review finding)' {
            { Update-PfbBucketAuditFilter -BucketId 'bucket-1' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-Name is required*'

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'defaults the required "names" query parameter from -BucketName when -Name is not supplied' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['names'] -eq 'mybucket'
            }
        }

        It 'sends -Name as names when explicitly supplied, overriding the -BucketName default' {
            Update-PfbBucketAuditFilter -BucketId 'bucket-1' -Name 'custom-filter-name' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($QueryParams['names']).Count -eq 1 -and @($QueryParams['names'])[0] -eq 'custom-filter-name'
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbBucketAuditFilter -BucketName 'mybucket' -Attributes @{ actions = @('s3:GetObject') } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($Body['actions'])[0] -eq 's3:GetObject'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbBucketAuditFilter -BucketName 'mybucket' -Actions @('s3:GetObject') `
                -Attributes @{ actions = @('s3:PutObject') } -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }

        It 'rejects an unresolved selector plus typed parameter plus -Attributes' {
            { Update-PfbBucketAuditFilter -BucketId 'bucket-1' -S3Prefixes @('p1') `
                -Attributes @{ s3_prefixes = @('p2') } -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Actions' }
            @{ Parameter = 'S3Prefixes' }
        ) {
            $attrs = (Get-Command Update-PfbBucketAuditFilter).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'exposes every settable body field the endpoint accepts' {
            $keys = (Get-Command Update-PfbBucketAuditFilter).Parameters.Keys
            foreach ($p in 'Actions', 'S3Prefixes') {
                $keys | Should -Contain $p
            }
        }
    }
}
