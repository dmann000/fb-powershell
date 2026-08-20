#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    # A throwaway connection object; Assert-PfbConnection is mocked so its contents don't matter.
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'New-PfbFileSystemSnapshot' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'makes one API call PER explicit -SourceName (FlashBlade rejects multi-source snapshot creation)' {
        New-PfbFileSystemSnapshot -SourceName 'fs1', 'fs2' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 2 -Exactly
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq 'file-system-snapshots' -and $QueryParams['source_names'] -eq 'fs1'
        }
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['source_names'] -eq 'fs2'
        }
    }

    It 'issues a separate API call per piped FileSystem object (regression: must not batch into one call or only process the last)' {
        $fsObjects = @(
            [pscustomobject]@{ name = 'fs1' }
            [pscustomobject]@{ name = 'fs2' }
            [pscustomobject]@{ name = 'fs3' }
        )
        $fsObjects | New-PfbFileSystemSnapshot -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 3 -Exactly
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['source_names'] -eq 'fs1'
        }
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['source_names'] -eq 'fs2'
        }
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $QueryParams['source_names'] -eq 'fs3'
        }
    }

    It 'passes suffix in the body when -Suffix is supplied' {
        New-PfbFileSystemSnapshot -SourceName 'fs1' -Suffix 'daily-backup' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Body['suffix'] -eq 'daily-backup'
        }
    }

    It 'makes zero API calls under -WhatIf' {
        New-PfbFileSystemSnapshot -SourceName 'fs1' -WhatIf -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }
}
