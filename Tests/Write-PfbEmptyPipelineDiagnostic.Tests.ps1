#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# Issue #126. Broadening suppression broadens silence, which is in tension with #121's finding
# that silence is the dangerous direction. These assertions pin the compromise: verbose always,
# warning only where the caller supplied something that was thrown away.

BeforeAll {
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Write-PfbEmptyPipelineDiagnostic' {

    It 'writes verbose and no warning when nothing the caller typed was discarded' {
        # The load-bearing half of the split. An empty pipeline with no keys bound is ORDINARY
        # no-match operation; warning here is what would train users to redirect the stream.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end { Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet -DiscardedKey @() }
            }

            $records = @(@() | Invoke-DiagFixture -Verbose 3>&1 4>&1)
            @($records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Count |
                Should -Be 1
            @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
                Should -Be 0
        }
    }

    It 'writes both verbose and warning when keys were discarded' {
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end { Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet -DiscardedKey @('limit') }
            }

            $records = @(@() | Invoke-DiagFixture -Limit 10 -Verbose 3>&1 4>&1)
            @($records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Count |
                Should -Be 1
            @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
                Should -Be 1
        }
    }

    It 'emits no verbose record without -Verbose, and still warns' {
        # Proves the verbose line costs nothing by default, and that the warning does not ride on
        # the verbose preference.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end { Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet -DiscardedKey @('limit') }
            }

            $records = @(@() | Invoke-DiagFixture -Limit 10 3>&1 4>&1)
            @($records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Count |
                Should -Be 0
            @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
                Should -Be 1
        }
    }

    It 'honours the caller -WarningAction' {
        # This is what makes "a preference-controlled stream is adequate" a true statement rather
        # than an assumption -- the caller really can turn it off, and the suppression still happens.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end { Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet -DiscardedKey @('limit') }
            }

            $records = @(@() | Invoke-DiagFixture -Limit 10 -WarningAction SilentlyContinue 3>&1 4>&1)
            @($records | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count |
                Should -Be 0
        }
    }

    It 'names the cmdlet, the caller own parameters, and falls back to the wire key' {
        # -Limit resolves through metadata; 'protocols' cannot, because the parameter is
        # -Protocol. Both must appear in one message, so a regression to either "always the
        # parameter" or "always the wire key" reds.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param(
                    [Parameter(ValueFromPipeline)][string]$Name,
                    [int]$Limit,
                    [string[]]$Protocol
                )
                end {
                    Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet -DiscardedKey @('protocols', 'limit')
                }
            }

            $warning = @(@() | Invoke-DiagFixture -Limit 10 -Protocol smb 3>&1 |
                    Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warning.Count | Should -Be 1

            $text = [string]$warning[0].Message
            $text | Should -BeLike '*Invoke-DiagFixture*'
            $text | Should -BeLike '*-Limit*'
            $text | Should -BeLike "*'protocols'*"

            # Pinned whole, not by substring: concatenating four fragments is exactly where a
            # missing or doubled space hides, and a -BeLike per clause cannot see one.
            $text | Should -Be (
                'Invoke-DiagFixture received an empty pipeline, so no object was selected. ' +
                "-Limit, 'protocols' can only narrow or shape a result set, not select objects, " +
                'so no request was issued. If you did not intend to filter, call ' +
                'Invoke-DiagFixture directly instead of piping to it.')
        }
    }

    It 'reads grammatically when exactly one key was discarded' {
        # The single-key case is the common one, and "-Limit narrow or shape a result set" was not
        # a sentence. The modal has to carry both numbers without branching on the count.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name, [int]$Limit)
                end { Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet -DiscardedKey @('limit') }
            }

            $warning = @(@() | Invoke-DiagFixture -Limit 10 3>&1 |
                    Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $warning.Count | Should -Be 1

            [string]$warning[0].Message | Should -Be (
                'Invoke-DiagFixture received an empty pipeline, so no object was selected. ' +
                '-Limit can only narrow or shape a result set, not select objects, ' +
                'so no request was issued. If you did not intend to filter, call ' +
                'Invoke-DiagFixture directly instead of piping to it.')
        }
    }

    It 'orders the discarded keys ordinally, so the message is edition-stable' {
        # Sort-Object's invariant linguistic order is NOT edition-stable between 5.1 and 7, and
        # this string is asserted on. Ordinal is the only ordering both editions agree about.
        InModuleScope PureStorageFlashBladePowerShell {
            function Invoke-DiagFixture {
                [CmdletBinding()]
                param([Parameter(ValueFromPipeline)][string]$Name)
                end {
                    Write-PfbEmptyPipelineDiagnostic -Caller $PSCmdlet `
                        -DiscardedKey @('total_only', 'destroyed', 'end_time')
                }
            }

            $warning = @(@() | Invoke-DiagFixture 3>&1 |
                    Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
            $text = [string]$warning[0].Message

            $text | Should -BeLike "*'destroyed', 'end_time', 'total_only'*"
        }
    }
}
