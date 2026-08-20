#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbLifecycleRule - typed body and query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed body parameters' {
        It 'sends -Prefix as the prefix body field' {
            Update-PfbLifecycleRule -Name 'archive' -Prefix 'old/' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'lifecycle-rules' -and
                $QueryParams['names'] -eq 'archive' -and
                $Body['prefix'] -eq 'old/'
            }
        }

        It 'sends an explicit -Enabled:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbLifecycleRule -Name 'cleanup' -Enabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('enabled') -and $Body['enabled'] -eq $false
            }
        }

        It 'sends an explicit -AbortIncompleteMultipartUploadsAfter 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbLifecycleRule -Name 'cleanup' -AbortIncompleteMultipartUploadsAfter 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('abort_incomplete_multipart_uploads_after') -and
                $Body['abort_incomplete_multipart_uploads_after'] -eq 0
            }
        }

        It 'sends -KeepCurrentVersionFor, -KeepCurrentVersionUntil and -KeepPreviousVersionFor as integer fields' {
            Update-PfbLifecycleRule -Name 'cleanup' -KeepCurrentVersionFor 5184000000 `
                -KeepCurrentVersionUntil 7776000000 -KeepPreviousVersionFor 2592000000 `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['keep_current_version_for'] -eq 5184000000 -and
                $Body['keep_current_version_until'] -eq 7776000000 -and
                $Body['keep_previous_version_for'] -eq 2592000000
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbLifecycleRule -Name 'cleanup' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the lifecycle rule by id when -Id is used' {
            Update-PfbLifecycleRule -Id 'rule-1' -Prefix 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'rule-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context 'typed query parameters (bare, not in Individual sets -- constraint 17)' {
        It 'joins -BucketIds and -BucketNames with commas' {
            Update-PfbLifecycleRule -Name 'archive' -BucketIds 'b-1', 'b-2' -BucketNames 'bkt1', 'bkt2' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['bucket_ids'] -eq 'b-1,b-2' -and $QueryParams['bucket_names'] -eq 'bkt1,bkt2'
            }
        }

        It 'sends -ConfirmDate as an explicit 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbLifecycleRule -Name 'archive' -ConfirmDate 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('confirm_date') -and $QueryParams['confirm_date'] -eq 0
            }
        }

        It 'combines a query parameter with -Attributes without a set conflict' {
            Update-PfbLifecycleRule -Name 'archive' -Attributes @{ prefix = 'raw/' } -BucketNames 'bkt1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['prefix'] -eq 'raw/' -and $QueryParams['bucket_names'] -eq 'bkt1'
            }
        }

        It 'omits bucket_ids, bucket_names and confirm_date entirely when not supplied' {
            Update-PfbLifecycleRule -Name 'archive' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('bucket_ids') -and
                -not $QueryParams.ContainsKey('bucket_names') -and
                -not $QueryParams.ContainsKey('confirm_date')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbLifecycleRule -Name 'archive' -Attributes @{ prefix = 'raw/' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['prefix'] -eq 'raw/'
            }
        }

        It 'rejects -Attributes combined with a typed BODY parameter at bind time' {
            { Update-PfbLifecycleRule -Name 'archive' -Prefix 'x' -Attributes @{ prefix = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }
}
