#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Remove-PfbFileSystemSession' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It 'has no -Id parameter (the endpoint has no ids query parameter in any spec version)' {
        (Get-Command Remove-PfbFileSystemSession).Parameters.ContainsKey('Id') | Should -BeFalse
    }

    It 'restricts -Protocol to the two real spec-documented values' {
        $attr = (Get-Command Remove-PfbFileSystemSession).Parameters['Protocol'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $attr | Should -Not -BeNullOrEmpty
        $attr.ValidValues | Should -Be @('nfs', 'smb')
    }

    It 'rejects an invalid -Protocol value before making any API call' {
        { Remove-PfbFileSystemSession -Protocol 'bogus' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'rejects combining -Name and -Protocol (true mutual exclusivity, matching the server)' {
        { Remove-PfbFileSystemSession -Name 'some-session-name' -Protocol 'nfs' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'terminates a single session by its own session name via -Name, sending only names' {
        Remove-PfbFileSystemSession -Name '22517998136858346-smb' -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'file-systems/sessions' -and
            $QueryParams['names'] -eq '22517998136858346-smb' -and
            -not $QueryParams.ContainsKey('protocols') -and -not $QueryParams.ContainsKey('disruptive')
        }
    }

    It 'bulk-terminates by -Protocol, sending protocols comma-joined plus the required disruptive flag' {
        Remove-PfbFileSystemSession -Protocol 'nfs', 'smb' -Force -Confirm:$false -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Endpoint -eq 'file-systems/sessions' -and
            $QueryParams['protocols'] -eq 'nfs,smb' -and $QueryParams['disruptive'] -eq 'true' -and
            -not $QueryParams.ContainsKey('names')
        }
    }

    It 'requires -Force for the -Protocol bulk path, independent of $ConfirmPreference (rejects -Protocol without -Force even with -Confirm:$false)' {
        { Remove-PfbFileSystemSession -Protocol 'smb' -Confirm:$false -Array $fakeArray } | Should -Throw
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'honors -WhatIf for the -Name path (no call made)' {
        Remove-PfbFileSystemSession -Name '22517998136858346-smb' -WhatIf -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }

    It 'honors -WhatIf for the -Protocol bulk path (no call made)' {
        Remove-PfbFileSystemSession -Protocol 'smb' -Force -WhatIf -Array $fakeArray
        Should -Invoke Invoke-PfbApiRequest -ModuleName PureStorageFlashBladePowerShell -Times 0 -Exactly
    }
}
