#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Issue #126. Renders a wire query key for a user-facing message. snake_case -> PascalCase is a
# guess; checking it against the caller's own parameter metadata is what stops it being one.

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Resolve-PfbQueryKeyDisplayName' {

    It 'names the caller own parameter when the metadata confirms one' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-ResolverFixture {
                [CmdletBinding()]
                param(
                    [Parameter(ValueFromPipeline)][string]$Name,
                    [int]$Limit,
                    [switch]$TotalOnly,
                    [datetime]$StartTime
                )
                end {
                    foreach ($key in @('limit', 'total_only', 'start_time')) {
                        Resolve-PfbQueryKeyDisplayName -Caller $PSCmdlet -WireName $key
                    }
                }
            }

            $actual = @(Invoke-ResolverFixture)
            $actual | Should -Be @('-Limit', '-TotalOnly', '-StartTime')
        }
    }

    It 'falls back to the quoted wire key when the derived name is not a parameter' {
        # The measured case, not a hypothetical: Get-PfbFileSystemSession writes 'protocols' from
        # a parameter named -Protocol. A message naming "-Protocols" would send the caller to a
        # parameter that does not exist.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-ResolverFixture {
                [CmdletBinding()]
                param(
                    [Parameter(ValueFromPipeline)][string]$Name,
                    [string[]]$Protocol
                )
                end { Resolve-PfbQueryKeyDisplayName -Caller $PSCmdlet -WireName 'protocols' }
            }

            Invoke-ResolverFixture | Should -Be "'protocols'"
        }
    }

    It 'is a real check against the real cmdlet, not a hardcoded table' {
        # Non-vacuity. The SAME wire key must resolve differently for two callers that differ
        # only in whether they declare the parameter. Hardcode either answer and one half reds.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-WithDestroyed {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [switch]$Destroyed)
                end { Resolve-PfbQueryKeyDisplayName -Caller $PSCmdlet -WireName 'destroyed' }
            }
            function Invoke-WithoutDestroyed {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Resolve-PfbQueryKeyDisplayName -Caller $PSCmdlet -WireName 'destroyed' }
            }

            Invoke-WithDestroyed    | Should -Be '-Destroyed'
            Invoke-WithoutDestroyed | Should -Be "'destroyed'"
        }
    }

    It 'resolves every listed non-selector key against a real shipped cmdlet' {
        # Guards the transform against a key shape it cannot handle. Eleven resolve; 'protocols'
        # is the known and deliberate miss. If a twelfth ever starts missing, the message quietly
        # degrades to wire keys and nobody notices -- so pin the split.
        #
        # NOTE ON WHAT THIS ASSERTS. This block does NOT call Resolve-PfbQueryKeyDisplayName; it
        # reimplements the transform below and asserts the TREE's conformance to it -- that each
        # listed wire key does or does not correspond to a declared parameter on the shipped cmdlet
        # that writes it. Calling the function here is not possible: its -Caller is a live
        # [PSCmdlet], which the runtime only materialises inside an executing advanced function, so
        # obtaining one for Get-PfbFileSystem would mean actually invoking Get-PfbFileSystem.
        #
        # The function's own behaviour is covered by the three Its above, which call it for real
        # through fixture functions with a genuine $PSCmdlet, and end to end by
        # Tests/Write-PfbEmptyPipelineDiagnostic.Tests.ps1, which pins the rendered message.
        # What is duplicated here is the transform, and the two copies diverging is precisely what
        # the three Its above would catch.
        $cases = @(
            @{ Key = 'limit';              Cmdlet = 'Get-PfbFileSystem';                          Expected = '-Limit' }
            @{ Key = 'sort';               Cmdlet = 'Get-PfbFileSystem';                          Expected = '-Sort' }
            @{ Key = 'total_only';         Cmdlet = 'Get-PfbFileSystem';                          Expected = '-TotalOnly' }
            @{ Key = 'destroyed';          Cmdlet = 'Get-PfbFileSystem';                          Expected = '-Destroyed' }
            @{ Key = 'start_time';         Cmdlet = 'Get-PfbArrayPerformanceReplication';         Expected = '-StartTime' }
            @{ Key = 'end_time';           Cmdlet = 'Get-PfbArrayPerformanceReplication';         Expected = '-EndTime' }
            @{ Key = 'resolution';         Cmdlet = 'Get-PfbArrayPerformanceReplication';         Expected = '-Resolution' }
            @{ Key = 'current_fleet_only'; Cmdlet = 'Get-PfbRemoteArray';                         Expected = '-CurrentFleetOnly' }
            @{ Key = 'type';               Cmdlet = 'Get-PfbArrayConnectionPerformanceReplication'; Expected = '-Type' }
            @{ Key = 'flagged';            Cmdlet = 'Get-PfbAlert';                               Expected = '-Flagged' }
            @{ Key = 'expose_api_token';   Cmdlet = 'Get-PfbApiToken';                            Expected = '-ExposeApiToken' }
            @{ Key = 'protocols';          Cmdlet = 'Get-PfbFileSystemSession';                   Expected = "'protocols'" }
        )

        foreach ($case in $cases) {
            $command = Get-Command -Module PureStorageFlashBladePowerShell -Name $case.Cmdlet
            $command | Should -Not -BeNullOrEmpty -Because "$($case.Cmdlet) must exist for this case to mean anything"

            $candidate = -join @(($case.Key -split '_') | ForEach-Object {
                    if ($_.Length -eq 0) { '' }
                    else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
                })
            $rendered = if ($command.Parameters.ContainsKey($candidate)) { "-$candidate" } else { "'$($case.Key)'" }

            $rendered | Should -Be $case.Expected -Because "$($case.Key) on $($case.Cmdlet)"
        }
    }
}
