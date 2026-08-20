#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest   = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Update-PfbLogTargetObjectStore - typed body parameters (#31)' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    Context 'typed parameters build the body' {
        It 'sends name as a body field' {
            Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -NewName 'renamed-target' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Endpoint -eq 'log-targets/object-store' -and
                $QueryParams['names'] -eq 'log-obj-target1' -and
                $Body['name'] -eq 'renamed-target'
            }
        }

        It 'builds bucket as a name-reference object (constraint 8a, scalar reference)' {
            Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -Bucket 'bucket1' `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['bucket'].name -eq 'bucket1'
            }
        }

        It 'passes log_name_prefix through as a composite hashtable (constraint 8c)' {
            Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -LogNamePrefix @{ prefix = 's3auditlog' } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['log_name_prefix']['prefix'] -eq 's3auditlog'
            }
        }

        It 'passes log_rotate through as a composite hashtable (constraint 8c)' {
            Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -LogRotate @{ duration = 300000 } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['log_rotate']['duration'] -eq 300000
            }
        }

        It 'omits every body key when no typed body parameter is supplied' {
            Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body.Count -eq 0
            }
        }

        It 'targets the log target by id when -Id is used' {
            Update-PfbLogTargetObjectStore -Id 'lt-1' -NewName 'x' -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['ids'] -eq 'lt-1' -and -not $QueryParams.ContainsKey('names')
            }
        }
    }

    Context '-Attributes remains supported and is mutually exclusive' {
        It 'still sends a raw -Attributes body' {
            Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -Attributes @{ bucket = @{ name = 'raw-bucket' } } `
                -Confirm:$false -Array $fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Body['bucket']['name'] -eq 'raw-bucket'
            }
        }

        It 'rejects -Attributes combined with a typed parameter at bind time' {
            { Update-PfbLogTargetObjectStore -Name 'log-obj-target1' -NewName 'x' -Attributes @{ name = 'y' } `
                -Confirm:$false -Array $fakeArray -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Parameter set cannot be resolved*'
        }
    }

    Context 'constraint compliance' {
        It 'puts no ValidateSet on -<Parameter> (constraint 3, no spec enum)' -ForEach @(
            @{ Parameter = 'Bucket' }
            @{ Parameter = 'LogNamePrefix' }
            @{ Parameter = 'LogRotate' }
            @{ Parameter = 'NewName' }
        ) {
            $attrs = (Get-Command Update-PfbLogTargetObjectStore).Parameters[$Parameter].Attributes
            @($attrs | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count |
                Should -Be 0
        }

        It 'has no -LogTargetObjectStoreName parameter (the "name" body field uses -NewName per the exception)' {
            (Get-Command Update-PfbLogTargetObjectStore).Parameters.Keys | Should -Not -Contain 'LogTargetObjectStoreName'
        }
    }
}
