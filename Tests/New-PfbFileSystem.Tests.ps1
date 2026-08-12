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

    Context 'snapshot directory passthrough' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
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
}
