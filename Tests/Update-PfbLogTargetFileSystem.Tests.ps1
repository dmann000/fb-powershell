#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbLogTargetFileSystem - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends keep_for, keep_size and name as body fields' {
            Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -KeepFor 86400000 -KeepSize 1000000 `
                -NewName 'renamed-target' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'log-targets/file-systems' -and
                $QueryParams['names'] -eq 'log-fs-target1' -and
                $Body['keep_for'] -eq 86400000 -and
                $Body['keep_size'] -eq 1000000 -and
                $Body['name'] -eq 'renamed-target'
            }
        }

        It 'sends an explicit -KeepFor 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -KeepFor 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('keep_for') -and $Body['keep_for'] -eq 0
            }
        }

        It 'sends an explicit -KeepSize 0 rather than dropping it (constraint 2, integer field)' {
            Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -KeepSize 0 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('keep_size') -and $Body['keep_size'] -eq 0
            }
        }

        It 'builds file_system as a name-reference object (constraint 8a, scalar reference)' {
            Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -FileSystem 'fs1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['file_system'].name -eq 'fs1'
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the log target by id when -Id is used' {
            Update-PfbLogTargetFileSystem -Id 'lt-1' -KeepFor 1 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'lt-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -Attributes @{ keep_for = 86400000 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['keep_for'] -eq 86400000
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbLogTargetFileSystem -Name 'log-fs-target1' -KeepFor 1 -Attributes @{ keep_for = 2 } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'FileSystem' }
            @{ Parameter = 'KeepFor' }
            @{ Parameter = 'KeepSize' }
            @{ Parameter = 'NewName' }
        ) {
            $attrs = (Get-Command Update-PfbLogTargetFileSystem).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'has no -LogTargetFileSystemName parameter (the "name" body field uses -NewName per the exception)' {
            (Get-Command Update-PfbLogTargetFileSystem).Parameters.Keys | Should -Not -Contain 'LogTargetFileSystemName'
        }

        It 'does not expose the read-only id field as a parameter (constraint 11)' {
            (Get-Command Update-PfbLogTargetFileSystem).Parameters.Keys | Should -Not -Contain 'IdField'
        }
    }
}
