#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1') -Force
    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.26'; AuthToken = 'x' }
}

Describe 'New-PfbFileSystem - request construction baseline' {

    Context 'endpoint, method and name selector' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'POSTs to file-systems with the file system name in the names query parameter' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'file-systems' -and
                $QueryParams['names'] -eq 'fs01'
            }
        }

        It 'does not put the name into the request body' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('name') -and -not $Body.ContainsKey('names')
            }
        }

        It 'sends provisioned and hard_limit_enabled when a size with a hard limit is requested' {
            New-PfbFileSystem -Name 'fs01' -Provisioned 1073741824 -HardLimit -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['provisioned'] -eq 1073741824 -and
                $Body['hard_limit_enabled'] -eq $true
            }
        }
    }

    Context 'NFS body construction' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'enables both NFS versions under the nfs key for -Nfs' {
            New-PfbFileSystem -Name 'fs01' -Nfs -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['nfs']['v3_enabled'] -eq $true -and
                $Body['nfs']['v4_1_enabled'] -eq $true
            }
        }

        It 'enables NFSv3 only for -NfsV3' {
            New-PfbFileSystem -Name 'fs01' -NfsV3 -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['nfs']['v3_enabled'] -eq $true -and
                -not $Body['nfs'].ContainsKey('v4_1_enabled')
            }
        }

        It 'nests the NFS export policy as a reference object' {
            New-PfbFileSystem -Name 'fs01' -Nfs -NfsExportPolicy 'nfs-rw-eng' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['nfs']['export_policy']['name'] -eq 'nfs-rw-eng' -and
                -not $Body['nfs'].ContainsKey('rules')
            }
        }

        It 'omits the nfs key entirely when no NFS parameter is supplied' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('nfs')
            }
        }

        It 'throws when both -NfsExportPolicy and -NfsRules are supplied' {
            { New-PfbFileSystem -Name 'fs01' -NfsExportPolicy 'nfs-rw-eng' -NfsRules '10.0.0.0/8(rw)' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage '*only one of -NfsExportPolicy or -NfsRules*'
        }
    }

    Context 'SMB body construction' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'sets smb.enabled and nests the share and client policies' {
            New-PfbFileSystem -Name 'fs01' -Smb -SmbSharePolicy 'smb-rw' -SmbClientPolicy 'smb-clients' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb']['enabled'] -eq $true -and
                $Body['smb']['share_policy']['name'] -eq 'smb-rw' -and
                $Body['smb']['client_policy']['name'] -eq 'smb-clients'
            }
        }

        It 'enables SMB and warns when no share policy is supplied' {
            New-PfbFileSystem -Name 'fs01' -Smb -Confirm:$false -Array $fakeArray -WarningAction SilentlyContinue -WarningVariable smbWarning

            $smbWarning | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb']['enabled'] -eq $true -and
                -not $Body['smb'].ContainsKey('share_policy')
            }
        }

        It 'omits the smb key entirely when no SMB parameter is supplied' {
            New-PfbFileSystem -Name 'fs01' -Nfs -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('smb')
            }
        }

        It 'sends the multi-protocol access control style when NFS and SMB are combined' {
            New-PfbFileSystem -Name 'fs01' -Nfs -Smb -SmbSharePolicy 'smb-rw' `
                -MultiProtocolAccessControlStyle 'shared' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['multi_protocol']['access_control_style'] -eq 'shared'
            }
        }
    }

    Context 'SMB continuous availability' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'exposes -SmbContinuousAvailabilityEnabled as a nullable bool, not a switch' {
            $p = (Get-Command New-PfbFileSystem).Parameters['SmbContinuousAvailabilityEnabled']
            $p.ParameterType | Should -Be ([Nullable[bool]])
            $p.SwitchParameter | Should -BeFalse
        }

        It 'omits continuous_availability_enabled entirely when the parameter is not supplied' {
            New-PfbFileSystem -Name 'fs01' -Smb -SmbSharePolicy 'smb-rw' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body['smb'].ContainsKey('continuous_availability_enabled')
            }
        }

        It 'omits the smb key entirely when neither SMB nor continuous availability is supplied' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('smb')
            }
        }

        It 'sends continuous_availability_enabled=true alongside an SMB enablement request' {
            New-PfbFileSystem -Name 'fs01' -Smb -SmbSharePolicy 'smb-rw' -SmbContinuousAvailabilityEnabled $true `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb']['enabled'] -eq $true -and
                $Body['smb']['continuous_availability_enabled'] -eq $true -and
                $Body['smb']['continuous_availability_enabled'] -is [bool]
            }
        }

        It 'sends continuous_availability_enabled=false when explicitly disabled' {
            New-PfbFileSystem -Name 'fs01' -Smb -SmbSharePolicy 'smb-rw' -SmbContinuousAvailabilityEnabled $false `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb'].ContainsKey('continuous_availability_enabled') -and
                $Body['smb']['continuous_availability_enabled'] -eq $false -and
                $Body['smb']['continuous_availability_enabled'] -is [bool]
            }
        }

        It 'does not set smb.enabled when only continuous availability is supplied' {
            New-PfbFileSystem -Name 'fs01' -SmbContinuousAvailabilityEnabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('smb') -and
                -not $Body['smb'].ContainsKey('enabled') -and
                $Body['smb']['continuous_availability_enabled'] -eq $true -and
                $Body['smb'].Count -eq 1
            }
        }

        It 'does not warn about a missing share policy when only continuous availability is supplied' {
            New-PfbFileSystem -Name 'fs01' -SmbContinuousAvailabilityEnabled $false -Confirm:$false -Array $fakeArray `
                -WarningAction SilentlyContinue -WarningVariable caWarning

            $caWarning | Should -BeNullOrEmpty
        }

        It 'still warns when SMB is enabled without a share policy even with continuous availability supplied' {
            New-PfbFileSystem -Name 'fs01' -Smb -SmbContinuousAvailabilityEnabled $true -Confirm:$false -Array $fakeArray `
                -WarningAction SilentlyContinue -WarningVariable smbWarning

            $smbWarning | Should -Not -BeNullOrEmpty
        }

        It 'does not create default exports merely because continuous availability is supplied' {
            New-PfbFileSystem -Name 'fs01' -SmbContinuousAvailabilityEnabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['default_exports'].Count -eq 1 -and
                $QueryParams['default_exports'][0] -eq ''
            }
        }

        It 'leaves an -Attributes body untouched and rejects the typed continuous-availability parameter' {
            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = @{ enabled = $true } } `
                    -SmbContinuousAvailabilityEnabled $true -Confirm:$false -Array $fakeArray } |
                Should -Throw

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'snapshot directory default' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'sends snapshot_directory_enabled=false when -SnapshotDirectoryEnabled is omitted' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('snapshot_directory_enabled') -and
                $Body['snapshot_directory_enabled'] -eq $false
            }
        }

        It 'sends a real [bool] rather than a nullable or string value when omitted' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['snapshot_directory_enabled'] -is [bool]
            }
        }

        It 'sends a real [bool] when -SnapshotDirectoryEnabled is explicit' {
            New-PfbFileSystem -Name 'fs01' -SnapshotDirectoryEnabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['snapshot_directory_enabled'] -is [bool]
            }
        }

        It 'leaves an -Attributes body without a synthetic snapshot_directory_enabled key' {
            New-PfbFileSystem -Name 'fs01' -Attributes @{ provisioned = 42 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 1 -and
                -not $Body.ContainsKey('snapshot_directory_enabled')
            }
        }

        It 'passes an -Attributes snapshot_directory_enabled value through untouched' {
            New-PfbFileSystem -Name 'fs01' -Attributes @{ snapshot_directory_enabled = $true } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 1 -and
                $Body['snapshot_directory_enabled'] -eq $true
            }
        }

        It 'sends snapshot_directory_enabled=true when -SnapshotDirectoryEnabled $true' {
            New-PfbFileSystem -Name 'fs01' -SnapshotDirectoryEnabled $true -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('snapshot_directory_enabled') -and
                $Body['snapshot_directory_enabled'] -eq $true
            }
        }

        It 'sends snapshot_directory_enabled=false when -SnapshotDirectoryEnabled $false' {
            New-PfbFileSystem -Name 'fs01' -SnapshotDirectoryEnabled $false -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('snapshot_directory_enabled') -and
                $Body['snapshot_directory_enabled'] -eq $false
            }
        }

        It 'exposes -SnapshotDirectoryEnabled as a nullable bool, not a switch' {
            $p = (Get-Command New-PfbFileSystem).Parameters['SnapshotDirectoryEnabled']
            $p.ParameterType | Should -Be ([Nullable[bool]])
            $p.SwitchParameter | Should -BeFalse
        }
    }

    Context 'Attributes parameter set' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'passes the supplied hashtable through as the request body verbatim' {
            New-PfbFileSystem -Name 'fs01' -Attributes @{ provisioned = 42; nfs = @{ v3_enabled = $true } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['provisioned'] -eq 42 -and
                $Body['nfs']['v3_enabled'] -eq $true -and
                $QueryParams['names'] -eq 'fs01'
            }
        }
    }

    Context 'default_exports query control' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'sends a single empty-string element when -DefaultExports is omitted' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams.ContainsKey('default_exports') -and
                $QueryParams['default_exports'] -is [array] -and
                @($QueryParams['default_exports']).Count -eq 1 -and
                @($QueryParams['default_exports'])[0] -eq ''
            }
        }

        It 'sends only nfs for -DefaultExports nfs' {
            New-PfbFileSystem -Name 'fs01' -DefaultExports 'nfs' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($QueryParams['default_exports']).Count -eq 1 -and
                @($QueryParams['default_exports'])[0] -eq 'nfs'
            }
        }

        It 'sends only smb for -DefaultExports smb' {
            # A default SMB export needs a named share policy, so this path always carries one.
            New-PfbFileSystem -Name 'fs01' -SmbSharePolicy 'smb-rw' -DefaultExports 'smb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($QueryParams['default_exports']).Count -eq 1 -and
                @($QueryParams['default_exports'])[0] -eq 'smb'
            }
        }

        It 'preserves order and both values for -DefaultExports nfs,smb' {
            New-PfbFileSystem -Name 'fs01' -SmbSharePolicy 'smb-rw' -DefaultExports 'nfs', 'smb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                @($QueryParams['default_exports']).Count -eq 2 -and
                @($QueryParams['default_exports'])[0] -eq 'nfs' -and
                @($QueryParams['default_exports'])[1] -eq 'smb'
            }
        }

        It 'rejects a protocol outside the published set at bind time' {
            { New-PfbFileSystem -Name 'fs01' -DefaultExports 'http' -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw
        }

        It 'never puts default_exports into the request body on the typed path' {
            New-PfbFileSystem -Name 'fs01' -DefaultExports 'nfs' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('default_exports')
            }
        }

        It 'leaves an -Attributes body untouched while still sending the query parameter' {
            New-PfbFileSystem -Name 'fs01' -Attributes @{ provisioned = 42 } -DefaultExports 'nfs' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 1 -and
                $Body['provisioned'] -eq 42 -and
                -not $Body.ContainsKey('default_exports') -and
                @($QueryParams['default_exports'])[0] -eq 'nfs'
            }
        }

        It 'suppresses default exports on the -Attributes path too when -DefaultExports is omitted' {
            New-PfbFileSystem -Name 'fs01' -Attributes @{ provisioned = 42 } -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 1 -and
                -not $Body.ContainsKey('default_exports') -and
                @($QueryParams['default_exports'])[0] -eq ''
            }
        }

        It 'serializes the omitted value to the exact wire form default_exports=' {
            # The value is taken from the cmdlet and handed to the real serializer, so this
            # covers the whole path rather than a believed-equivalent literal. A scalar empty
            # string would be dropped by ConvertTo-PfbQueryString and never reach the wire.
            # The mock returns $QueryParams so the cmdlet's own value can be read in the test
            # scope; the hashtable is then passed into the module by -Parameters, because a
            # variable set inside a mock body is not visible from InModuleScope.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { $QueryParams }

            $captured = New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ Captured = $captured } {
                param($Captured)
                ConvertTo-PfbQueryString -Parameters @{ default_exports = $Captured['default_exports'] } |
                    Should -Be '?default_exports='
            }
        }

        It 'serializes both protocols to the percent-encoded wire form default_exports=nfs%2Csmb' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { $QueryParams }

            $captured = New-PfbFileSystem -Name 'fs01' -SmbSharePolicy 'smb-rw' -DefaultExports 'nfs', 'smb' `
                -Confirm:$false -Array $fakeArray

            InModuleScope PureStorageFlashBladePowerShell -Parameters @{ Captured = $captured } {
                param($Captured)
                ConvertTo-PfbQueryString -Parameters @{ default_exports = $Captured['default_exports'] } |
                    Should -Be '?default_exports=nfs%2Csmb'
            }
        }

        It 'exposes -DefaultExports in both parameter sets' {
            $p = (Get-Command New-PfbFileSystem).Parameters['DefaultExports']
            $p.ParameterType | Should -Be ([string[]])
            $p.ParameterSets.Keys | Should -Contain '__AllParameterSets'
        }
    }

    Context 'default SMB export requires an explicit share policy' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'rejects -DefaultExports smb with no share policy and issues no request' {
            { New-PfbFileSystem -Name 'fs01' -DefaultExports 'smb' -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'rejects -DefaultExports nfs,smb with no share policy and issues no request' {
            { New-PfbFileSystem -Name 'fs01' -Nfs -Smb -DefaultExports 'nfs', 'smb' `
                    -Confirm:$false -Array $fakeArray -WarningAction SilentlyContinue } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'names the remedies in the rejection message' {
            { New-PfbFileSystem -Name 'fs01' -DefaultExports 'smb' -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*Pass -SmbSharePolicy or omit 'smb' from -DefaultExports.*"
        }

        It 'allows -DefaultExports smb when -SmbSharePolicy names a policy' {
            New-PfbFileSystem -Name 'fs01' -Smb -SmbSharePolicy 'smb-rw' -DefaultExports 'smb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb']['share_policy']['name'] -eq 'smb-rw' -and
                @($QueryParams['default_exports'])[0] -eq 'smb'
            }
        }

        It 'allows -DefaultExports nfs with no SMB policy' {
            New-PfbFileSystem -Name 'fs01' -Nfs -DefaultExports 'nfs' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
        }

        It 'allows an -Attributes body whose smb hashtable carries a share_policy' {
            New-PfbFileSystem -Name 'fs01' `
                -Attributes @{ smb = @{ enabled = $true; share_policy = @{ name = 'smb-rw' } } } `
                -DefaultExports 'smb' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb']['share_policy']['name'] -eq 'smb-rw'
            }
        }

        It 'allows an -Attributes body whose smb value is a ConvertFrom-Json PSCustomObject' {
            $smbObject = '{"enabled":true,"share_policy":{"name":"smb-rw"}}' | ConvertFrom-Json

            New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = $smbObject } `
                -DefaultExports 'smb' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['smb'].share_policy.name -eq 'smb-rw'
            }
        }

        It 'allows an -Attributes body whose smb value is a non-hashtable IDictionary' {
            $ordered = [ordered]@{ enabled = $true; share_policy = @{ name = 'smb-rw' } }

            New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = $ordered } -DefaultExports 'smb' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
        }

        It 'rejects an -Attributes body whose smb non-hashtable IDictionary lacks share_policy' {
            $ordered = [ordered]@{ enabled = $true }

            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = $ordered } -DefaultExports 'smb' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'rejects an -Attributes body with no smb key at all' {
            { New-PfbFileSystem -Name 'fs01' -Attributes @{ provisioned = 42 } -DefaultExports 'smb' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }

        It 'rejects an -Attributes body whose smb value is null' {
            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = $null } -DefaultExports 'smb' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'rejects an -Attributes body whose smb hashtable has no share_policy' {
            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = @{ enabled = $true } } `
                    -DefaultExports 'smb' -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'rejects an -Attributes body whose smb hashtable has a null share_policy' {
            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = @{ share_policy = $null } } `
                    -DefaultExports 'smb' -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'rejects an -Attributes body whose smb PSCustomObject has no share_policy property' {
            $smbObject = '{"enabled":true}' | ConvertFrom-Json

            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = $smbObject } -DefaultExports 'smb' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'rejects an -Attributes body whose smb PSCustomObject has a null share_policy' {
            $smbObject = '{"enabled":true,"share_policy":null}' | ConvertFrom-Json

            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = $smbObject } -DefaultExports 'smb' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'rejects an -Attributes body whose smb value is a non-dictionary scalar' {
            { New-PfbFileSystem -Name 'fs01' -Attributes @{ smb = 'enabled' } -DefaultExports 'smb' `
                    -Confirm:$false -Array $fakeArray } |
                Should -Throw -ExpectedMessage "*-DefaultExports includes 'smb' but no SMB share policy was supplied*"
        }

        It 'leaves the default call with no SMB body and an empty default_exports value' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('smb') -and
                @($QueryParams['default_exports']).Count -eq 1 -and
                @($QueryParams['default_exports'])[0] -eq ''
            }
        }
    }
}

Describe 'New-PfbFileSystem - default_exports REST 2.16 floor (mock-only)' {
    # Mock-only by necessity: the lab arrays run REST 2.26 and can never exercise the
    # pre-2.16 branch. Invoke-PfbApiRequest is deliberately NOT mocked -- the point is that
    # the real Assert-PfbApiCapability inside it fires against the real
    # Data/PfbCapabilityMap.json, which records default_exports on POST /file-systems at 2.16.

    BeforeAll {
        $script:oldArray = [PSCustomObject]@{
            Endpoint             = 'fb.example.test'
            ApiVersion           = '2.15'
            AuthToken            = 'session-token'
            BearerToken          = $null
            ApiToken             = 'T-fake-token'
            AuthMethod           = 'ApiToken'
            SkipCertificateCheck = $false
        }
    }

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { throw 'should never be called' }
    }

    It 'throws naming default_exports below REST 2.16 even when -DefaultExports is omitted' {
        { New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $oldArray } |
            Should -Throw -ExpectedMessage "*parameter 'default_exports' on POST /file-systems requires REST 2.16*Upgrade the array or omit the unsupported option(s).*"

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }

    It 'throws naming default_exports below REST 2.16 when -DefaultExports is explicit' {
        # -SmbSharePolicy keeps the default-SMB-export policy guard satisfied, so the version
        # gate is what this case actually exercises.
        { New-PfbFileSystem -Name 'fs01' -SmbSharePolicy 'smb-rw' -DefaultExports 'nfs', 'smb' `
                -Confirm:$false -Array $oldArray } |
            Should -Throw -ExpectedMessage "*parameter 'default_exports' on POST /file-systems requires REST 2.16*Upgrade the array or omit the unsupported option(s).*"

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod -Times 0 -Exactly
    }

    It 'does not gate on default_exports for an array at REST 2.16 or later' {
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod { [PSCustomObject]@{ items = @() } }

        $newArray = [PSCustomObject]@{
            Endpoint             = 'fb.example.test'
            ApiVersion           = '2.16'
            AuthToken            = 'session-token'
            BearerToken          = $null
            ApiToken             = 'T-fake-token'
            AuthMethod           = 'ApiToken'
            SkipCertificateCheck = $false
        }

        { New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $newArray } | Should -Not -Throw
    }
}

Describe 'New-PfbFileSystem - no per-filesystem eradication input' {
    # Remove incorrectly scoped per-filesystem eradication input from New-PfbFileSystem.

    Context 'command metadata' {

        It 'exposes no EradicationMode parameter' {
            $cmd = Get-Command New-PfbFileSystem
            $cmd.Parameters.Keys | Should -Not -Contain 'EradicationMode'
        }

        It 'exposes no ManualEradication parameter' {
            $cmd = Get-Command New-PfbFileSystem
            $cmd.Parameters.Keys | Should -Not -Contain 'ManualEradication'
        }

        It 'does not mention eradication in the cmdlet help text' {
            $helpText = Get-Help New-PfbFileSystem -Full | Out-String
            $helpText | Should -Not -Match 'eradication'
        }
    }

    Context 'request body construction' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'sends no eradication_config on a minimal typed call' {
            New-PfbFileSystem -Name 'fs01' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('eradication_config')
            }
        }

        It 'sends no eradication_config on a fully populated typed call' {
            New-PfbFileSystem -Name 'fs01' -Provisioned 1073741824 -HardLimit -Nfs -Smb `
                -SmbSharePolicy 'smb-rw' -MultiProtocolAccessControlStyle 'shared' `
                -GroupOwnership 'creator' -SnapshotDirectoryEnabled $true -Writable $true `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                -not $Body.ContainsKey('eradication_config')
            }
        }
    }
}
