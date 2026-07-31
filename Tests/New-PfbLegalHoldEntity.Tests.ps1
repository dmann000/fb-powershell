#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbLegalHoldEntity - query parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context '-HoldName/-MemberName are not exposed (whole-branch review: hold_names/member_names do not exist on this endpoint in any cached spec version)' {
        It 'has no -HoldName parameter' {
            (Get-Command New-PfbLegalHoldEntity).Parameters.Keys | Should -Not -Contain 'HoldName'
        }

        It 'has no -MemberName parameter' {
            (Get-Command New-PfbLegalHoldEntity).Parameters.Keys | Should -Not -Contain 'MemberName'
        }

        It 'never sends hold_names or member_names query parameters' {
            New-PfbLegalHoldEntity -Names 'litigation-hold-2024' -FileSystemNames 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Endpoint -eq 'legal-holds/held-entities' -and
                -not $QueryParams.ContainsKey('hold_names') -and -not $QueryParams.ContainsKey('member_names') -and
                $QueryParams['names'] -eq 'litigation-hold-2024' -and
                $QueryParams['file_system_names'] -eq 'fs1'
            }
        }
    }

    Context 'new query parameters' {
        It 'joins -FileSystemIds and -FileSystemNames with commas' {
            New-PfbLegalHoldEntity -FileSystemIds 'fsid-1', 'fsid-2' -FileSystemNames 'fs1', 'fs2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['file_system_ids'] -eq 'fsid-1,fsid-2' -and
                $QueryParams['file_system_names'] -eq 'fs1,fs2'
            }
        }

        It 'joins -Ids and -Names with commas' {
            New-PfbLegalHoldEntity -Ids 'id-1', 'id-2' -Names 'e1', 'e2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'id-1,id-2' -and
                $QueryParams['names'] -eq 'e1,e2'
            }
        }

        It 'sends an EMPTY array for -Ids @() so the query key still reaches the wire (constraint 2)' {
            New-PfbLegalHoldEntity -Ids @() -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('ids') -and @($QueryParams['ids'] -split ',' | Where-Object { $_ }).Count -eq 0
            }
        }

        It 'joins -Paths with commas' {
            New-PfbLegalHoldEntity -Paths '/dir1', '/dir2' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['paths'] -eq '/dir1,/dir2'
            }
        }

        It 'sends an explicit -Recursive:$false (ContainsKey semantics, not truthiness)' {
            New-PfbLegalHoldEntity -FileSystemNames 'fs1' -Recursive $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('recursive') -and $QueryParams['recursive'] -eq $false
            }
        }

        It 'sends -Recursive:$true when supplied' {
            New-PfbLegalHoldEntity -FileSystemNames 'fs1' -Recursive $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['recursive'] -eq $true
            }
        }

        It 'omits recursive entirely when not supplied' {
            New-PfbLegalHoldEntity -FileSystemNames 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $QueryParams.ContainsKey('recursive')
            }
        }
    }

    Context 'endpoint accepts no request body' {
        It 'sends an empty body when -Attributes is not supplied' {
            New-PfbLegalHoldEntity -FileSystemNames 'fs1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }
    }
}
