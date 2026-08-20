#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule
}

Describe 'Connect-PfbArray - capability-map staleness warning' {

    BeforeEach {
        # Negotiation + login mocks, shared by every case. The negotiated version is what
        # varies, so each It re-mocks the api_version call.
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-WebRequest {
            [PSCustomObject]@{ Headers = @{ 'x-auth-token' = 'tok' } }
        }
    }

    Context 'Array version exceeds the map coverage' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.28', '2.29') }
            } -ParameterFilter { $Uri -like '*api_version*' }

            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
                [PSCustomObject]@{ schemaVersion = 2; generatedFrom = @('2.0', '2.27', '2.28') }
            }
        }

        It 'warns exactly once, naming both versions and the Update-Module remedy' {
            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            # Assert the COUNT, not merely that a warning appeared -- "fires exactly once
            # per connection" is the actual contract, and a per-call implementation would
            # pass a mere-presence assertion.
            @($warnings).Count | Should -Be 1
            # Pin each version to its ROLE, not merely its presence. Asserting only that
            # '2.29' and '2.28' both appear somewhere lets the two be SWAPPED -- yielding
            # "running REST 2.28 ... covers through REST 2.29", which is backwards and
            # actively misleading -- while every test still passes.
            $warnings[0].ToString() | Should -BeLike '*running REST 2.29*'
            $warnings[0].ToString() | Should -BeLike '*covers through REST 2.28*'
            $warnings[0].ToString() | Should -BeLike '*Update-Module*'
            $conn | Should -Not -BeNullOrEmpty -Because 'a warning must not suppress the connection object'
        }

        It 'caches the verdict on the connection object' {
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningAction SilentlyContinue
            $conn.ExceedsCapabilityMapCoverage | Should -BeTrue
            $conn.ExceedsCapabilityMapCoverage | Should -BeOfType [bool] -Because 'never $null -- callers may test it directly'
        }

        It 'keeps the verdict OUT of the default display set' {
            # Deliberate: diagnostic state, not something every user should see when they type
            # $conn at the prompt, and adding it would change the default Format-List view for
            # every existing connection. Asserted because nothing else pins it -- adding the
            # property to $defaultProps otherwise passes the whole suite.
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningAction SilentlyContinue

            $displaySet = $conn.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $displaySet | Should -Not -Contain 'ExceedsCapabilityMapCoverage'
            # ...but it must still be reachable programmatically.
            $conn.PSObject.Properties.Name | Should -Contain 'ExceedsCapabilityMapCoverage'
        }

        It 'is suppressible with -WarningAction SilentlyContinue and emits nothing to the pipeline but the connection' {
            $output = @(Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningAction SilentlyContinue)
            $output.Count | Should -Be 1
            $output[0].PSObject.TypeNames | Should -Contain 'PureStorage.FlashBlade.Connection'
        }

        It 'makes no Gallery lookup to discover whether an update exists' {
            # Asserted over the AST's INVOKED COMMAND NAMES, not the source text. Two earlier
            # forms were both wrong:
            #   * Mock Find-Module -- Mock requires the command to EXIST, and PowerShellGet
            #     is not guaranteed loaded in a bare Windows PowerShell 5.1 host, so it fails
            #     there for reasons unrelated to this feature.
            #   * A raw text grep -- it fails on a harmless COMMENT mentioning Find-Module or
            #     a doc link to the Gallery. This very test's comment would trip it.
            # The AST sees only real command invocations, so comments and strings cannot
            # produce a false positive, and it is identical on both editions.
            # This module runs against air-gapped lab and customer arrays, so the warning
            # names the remedy rather than probing for it.
            $moduleRoot = Split-Path -Parent $PSScriptRoot
            $filesInCallGraph = @(
                'Public/Connection/Connect-PfbArray.ps1'
                'Private/Test-PfbCapabilityMapCoverage.ps1'
                'Private/Get-PfbCapabilityMap.ps1'
                'Private/ConvertTo-PfbVersionObject.ps1'
                'Private/Test-PfbVersionAtLeast.ps1'
            )

            foreach ($relativePath in $filesInCallGraph) {
                $fullPath = Join-Path $moduleRoot $relativePath
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$null, [ref]$null)
                $invoked = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                        ForEach-Object { $_.GetCommandName() })

                $invoked | Should -Not -Contain 'Find-Module' -Because "$relativePath must not probe the Gallery"
                $invoked | Should -Not -Contain 'Find-PSResource' -Because "$relativePath must not probe the Gallery"
                $invoked | Should -Not -Contain 'Update-Module' -Because "$relativePath must name the remedy, not perform it"
            }
        }
    }

    Context 'Array version is within the map coverage' {

        It 'is silent when the negotiated version equals the map maximum' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.26') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
                [PSCustomObject]@{ generatedFrom = @('2.0', '2.26') }
            }

            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 0
            $conn.ExceedsCapabilityMapCoverage | Should -BeFalse
        }

        It 'compares major/minor numerically, so 2.9 does not read as newer than 2.28' {
            # A string compare puts '2.9' above '2.28' -- a bug already found twice in this
            # repo. The arithmetic is Test-PfbVersionAtLeast's, not this feature's; this
            # asserts the delegation is actually wired up, since a hand-rolled comparison
            # would pass every other test in this file and fail only here.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.9') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
                [PSCustomObject]@{ generatedFrom = @('2.0', '2.28') }
            }

            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 0
            $conn.ExceedsCapabilityMapCoverage | Should -BeFalse
        }

        It 'finds the highest scanned version regardless of generatedFrom ordering' {
            # ConvertTo-PfbVersionObject sorts descending, so [0] is the max -- but do not
            # let that be satisfied incidentally by generatedFrom already being ascending.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.28') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
                [PSCustomObject]@{ generatedFrom = @('2.28', '2.9', '2.0', '2.10') }
            }

            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 0 -Because '2.28 is the max and equals the negotiated version'
            $conn.ExceedsCapabilityMapCoverage | Should -BeFalse
        }
    }

    Context 'The map is unavailable' {

        It 'is silent and reports $false when the map cannot be loaded' {
            # Get-PfbCapabilityMap returns $null for a missing manifest rather than
            # throwing; a missing map is "nothing to check against", never a hard failure,
            # and it must not become a warning either.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.28') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap { $null }

            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 0
            $conn.ExceedsCapabilityMapCoverage | Should -BeFalse
        }

        It 'is silent when generatedFrom is present but empty' {
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.28') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
                [PSCustomObject]@{ generatedFrom = @() }
            }

            $warnings = @()
            Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
            @($warnings).Count | Should -Be 0
        }

        It 'REGRESSION: still connects when loading the capability map THROWS' {
            # Get-PfbCapabilityMap returns $null for a missing file but does NOT guard
            # ConvertFrom-Json, so a corrupt shipped map throws. Before this feature that
            # surfaced at request time; it must not become a connect-time failure, or a bad
            # map would leave the user unable to connect at all to diagnose it.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.28') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap { throw 'corrupt manifest' }

            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            $conn | Should -Not -BeNullOrEmpty -Because 'a broken capability map must not break connecting'
            $conn.ExceedsCapabilityMapCoverage | Should -BeFalse
            @($warnings).Count | Should -Be 0
        }

        It 'is silent, and still connects, when generatedFrom holds an unparseable version' {
            # Both shared version helpers cast with [int] and do not guard their input, so a
            # garbage entry throws. That must degrade to silence -- never a warning, and
            # never a failed Connect-PfbArray, since the map is diagnostic and the
            # connection is the user's actual goal.
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-RestMethod {
                [PSCustomObject]@{ versions = @('2.28') }
            } -ParameterFilter { $Uri -like '*api_version*' }
            Mock -ModuleName PureStorageFlashBladePowerShell Get-PfbCapabilityMap {
                [PSCustomObject]@{ generatedFrom = @('not-a-version') }
            }

            $warnings = @()
            $conn = Connect-PfbArray -Endpoint 'fb.test' -ApiToken 'T-fake' -WarningVariable warnings -WarningAction SilentlyContinue

            @($warnings).Count | Should -Be 0
            $conn | Should -Not -BeNullOrEmpty
            $conn.ExceedsCapabilityMapCoverage | Should -BeFalse
        }
    }
}
