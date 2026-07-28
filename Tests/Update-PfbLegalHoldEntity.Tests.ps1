#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbLegalHoldEntity - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'existing -Name selector (regression, unchanged)' {
        It 'still sends -Name as names' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'legal-holds/held-entities' -and
                $QueryParams['names'] -eq 'fs1'
            }
        }
    }

    Context 'new query parameters' {
        It 'joins -FileSystemIds and -FileSystemNames with commas' {
            Update-PfbLegalHoldEntity -Name 'fs1' -FileSystemIds 'fsid-1', 'fsid-2' -FileSystemNames 'fs1', 'fs2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['file_system_ids'] -eq 'fsid-1,fsid-2' -and
                $QueryParams['file_system_names'] -eq 'fs1,fs2'
            }
        }

        It 'joins -Ids and -Paths with commas' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Ids 'id-1', 'id-2' -Paths '/dir1', '/dir2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'id-1,id-2' -and
                $QueryParams['paths'] -eq '/dir1,/dir2'
            }
        }

        It 'sends an EMPTY array for -Ids @() so the query key still reaches the wire (constraint 2)' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Ids @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('ids') -and @($QueryParams['ids'] -split ',' | Where-Object { $_ }).Count -eq 0
            }
        }

        It 'sends an explicit -Recursive:$false (ContainsKey semantics, not truthiness)' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Recursive $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('recursive') -and $QueryParams['recursive'] -eq $false
            }
        }

        It 'sends an explicit -Released:$true so a hold can be released' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Released $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('released') -and $QueryParams['released'] -eq $true
            }
        }

        It 'omits recursive and released entirely when not supplied' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('recursive') -and -not $QueryParams.ContainsKey('released')
            }
        }
    }

    Context 'endpoint accepts no request body' {
        It 'sends an empty body when -Attributes is not supplied' {
            Update-PfbLegalHoldEntity -Name 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }
}
