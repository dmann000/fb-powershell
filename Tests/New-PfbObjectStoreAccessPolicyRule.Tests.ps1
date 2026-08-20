#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# ShouldProcess WhatIf text is written to the PSHost, not to any redirectable stream, so
# `... -WhatIf *>&1` captures nothing and an assertion built on that is vacuous on BOTH
# Windows PowerShell 5.1 and PowerShell 7 (proved by Tests/ArrayConnection.ShouldProcessTarget.Tests.ps1).
# The WhatIf-target assertion below therefore runs the cmdlet in a private runspace whose host
# records every UI write. Nothing the recording host captures is ever emitted to the Pester
# output stream, so no host text leaks into the assertions.

class PfbRuleRecordingRawUI : System.Management.Automation.Host.PSHostRawUserInterface {
    [System.ConsoleColor]$Back = [System.ConsoleColor]::Black
    [System.ConsoleColor]$Fore = [System.ConsoleColor]::White
    [System.Management.Automation.Host.Coordinates]$Cursor = [System.Management.Automation.Host.Coordinates]::new(0, 0)
    [System.Management.Automation.Host.Coordinates]$Window = [System.Management.Automation.Host.Coordinates]::new(0, 0)
    [System.Management.Automation.Host.Size]$Buffer = [System.Management.Automation.Host.Size]::new(120, 500)
    [System.Management.Automation.Host.Size]$WinSize = [System.Management.Automation.Host.Size]::new(120, 50)

    [System.ConsoleColor] get_BackgroundColor() { return $this.Back }
    [void] set_BackgroundColor([System.ConsoleColor]$value) { $this.Back = $value }
    [System.ConsoleColor] get_ForegroundColor() { return $this.Fore }
    [void] set_ForegroundColor([System.ConsoleColor]$value) { $this.Fore = $value }
    [System.Management.Automation.Host.Coordinates] get_CursorPosition() { return $this.Cursor }
    [void] set_CursorPosition([System.Management.Automation.Host.Coordinates]$value) { $this.Cursor = $value }
    [int] get_CursorSize() { return 25 }
    [void] set_CursorSize([int]$value) { }
    [System.Management.Automation.Host.Size] get_BufferSize() { return $this.Buffer }
    [void] set_BufferSize([System.Management.Automation.Host.Size]$value) { $this.Buffer = $value }
    [System.Management.Automation.Host.Coordinates] get_WindowPosition() { return $this.Window }
    [void] set_WindowPosition([System.Management.Automation.Host.Coordinates]$value) { $this.Window = $value }
    [System.Management.Automation.Host.Size] get_WindowSize() { return $this.WinSize }
    [void] set_WindowSize([System.Management.Automation.Host.Size]$value) { $this.WinSize = $value }
    [System.Management.Automation.Host.Size] get_MaxPhysicalWindowSize() { return $this.WinSize }
    [System.Management.Automation.Host.Size] get_MaxWindowSize() { return $this.WinSize }
    [string] get_WindowTitle() { return 'PfbRuleRecordingHost' }
    [void] set_WindowTitle([string]$value) { }
    [bool] get_KeyAvailable() { return $false }
    [void] FlushInputBuffer() { }
    [System.Management.Automation.Host.KeyInfo] ReadKey([System.Management.Automation.Host.ReadKeyOptions]$options) {
        throw [System.NotImplementedException]::new()
    }
    [System.Management.Automation.Host.BufferCell[,]] GetBufferContents([System.Management.Automation.Host.Rectangle]$rectangle) {
        throw [System.NotImplementedException]::new()
    }
    [void] SetBufferContents([System.Management.Automation.Host.Coordinates]$origin, [System.Management.Automation.Host.BufferCell[,]]$contents) { }
    [void] SetBufferContents([System.Management.Automation.Host.Rectangle]$rectangle, [System.Management.Automation.Host.BufferCell]$fill) { }
    [void] ScrollBufferContents([System.Management.Automation.Host.Rectangle]$source, [System.Management.Automation.Host.Coordinates]$destination, [System.Management.Automation.Host.Rectangle]$clip, [System.Management.Automation.Host.BufferCell]$fill) { }
}

class PfbRuleRecordingUI : System.Management.Automation.Host.PSHostUserInterface {
    [System.Collections.Generic.List[string]]$Lines = [System.Collections.Generic.List[string]]::new()
    [PfbRuleRecordingRawUI]$Raw = [PfbRuleRecordingRawUI]::new()

    [System.Management.Automation.Host.PSHostRawUserInterface] get_RawUI() { return $this.Raw }
    [void] Write([string]$value) { $this.Lines.Add($value) }
    [void] Write([System.ConsoleColor]$f, [System.ConsoleColor]$b, [string]$value) { $this.Lines.Add($value) }
    [void] WriteLine() { $this.Lines.Add('') }
    [void] WriteLine([string]$value) { $this.Lines.Add($value) }
    [void] WriteLine([System.ConsoleColor]$f, [System.ConsoleColor]$b, [string]$value) { $this.Lines.Add($value) }
    [void] WriteDebugLine([string]$message) { $this.Lines.Add($message) }
    [void] WriteErrorLine([string]$message) { $this.Lines.Add($message) }
    [void] WriteVerboseLine([string]$message) { $this.Lines.Add($message) }
    [void] WriteWarningLine([string]$message) { $this.Lines.Add($message) }
    [void] WriteProgress([long]$sourceId, [System.Management.Automation.ProgressRecord]$record) { }
    [string] ReadLine() { throw [System.NotImplementedException]::new() }
    [System.Security.SecureString] ReadLineAsSecureString() { throw [System.NotImplementedException]::new() }
    [System.Collections.Generic.Dictionary[string, psobject]] Prompt([string]$caption, [string]$message, [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.FieldDescription]]$descriptions) {
        throw [System.NotImplementedException]::new()
    }
    [int] PromptForChoice([string]$caption, [string]$message, [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]]$choices, [int]$defaultChoice) {
        # Recorded rather than thrown so an accidental confirmation prompt shows up as data
        # instead of hanging. The answer is always "No" -- nothing must reach the wire.
        $this.Lines.Add("CONFIRM: $caption / $message")
        return 1
    }
    [System.Management.Automation.PSCredential] PromptForCredential([string]$caption, [string]$message, [string]$userName, [string]$targetName) {
        throw [System.NotImplementedException]::new()
    }
    [System.Management.Automation.PSCredential] PromptForCredential([string]$caption, [string]$message, [string]$userName, [string]$targetName, [System.Management.Automation.PSCredentialTypes]$allowedCredentialTypes, [System.Management.Automation.PSCredentialUIOptions]$options) {
        throw [System.NotImplementedException]::new()
    }
}

class PfbRuleRecordingHost : System.Management.Automation.Host.PSHost {
    # Named Sink, not UI: a field differing from the PSHost.UI property only in casing is
    # rejected as non-CLS-compliant when the runspace opens.
    [PfbRuleRecordingUI]$Sink = [PfbRuleRecordingUI]::new()
    [guid]$Id = [guid]::NewGuid()

    [string] get_Name() { return 'PfbRuleRecordingHost' }
    [version] get_Version() { return [version]'1.0.0' }
    [guid] get_InstanceId() { return $this.Id }
    [System.Management.Automation.Host.PSHostUserInterface] get_UI() { return $this.Sink }
    [System.Globalization.CultureInfo] get_CurrentCulture() { return [System.Globalization.CultureInfo]::InvariantCulture }
    [System.Globalization.CultureInfo] get_CurrentUICulture() { return [System.Globalization.CultureInfo]::InvariantCulture }
    [void] EnterNestedPrompt() { throw [System.NotImplementedException]::new() }
    [void] ExitNestedPrompt() { throw [System.NotImplementedException]::new() }
    [void] NotifyBeginApplication() { }
    [void] NotifyEndApplication() { }
    [void] SetShouldExit([int]$exitCode) { }
}

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $script:manifest = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $script:manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }
}

Describe 'New-PfbObjectStoreAccessPolicyRule requires a rule name on the wire (issue #106 Part 1)' {

    Context 'parameter metadata' {

        BeforeAll {
            $script:cmd = Get-Command New-PfbObjectStoreAccessPolicyRule -Module PureStorageFlashBladePowerShell
        }

        It 'declares a -Name parameter' {
            $script:cmd.Parameters.Keys | Should -Contain 'Name'
        }

        It 'types -Name as a single string' {
            $script:cmd.Parameters['Name'].ParameterType | Should -Be ([string])
        }

        It 'makes -Name mandatory' {
            @($script:cmd.Parameters['Name'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Mandatory }) | Should -Contain $true
        }

        It 'gives -Name positional slot 1' {
            @($script:cmd.Parameters['Name'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                ForEach-Object { $_.Position }) | Should -Contain 1
        }

        It 'keeps -PolicyName mandatory in positional slot 0' {
            $attrs = @($script:cmd.Parameters['PolicyName'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($attrs | ForEach-Object { $_.Position }) | Should -Contain 0
            @($attrs | ForEach-Object { $_.Mandatory }) | Should -Contain $true
        }

        It 'documents -Name in the comment-based help' {
            (Get-Help New-PfbObjectStoreAccessPolicyRule -Parameter Name).Description.Text |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'the request that goes on the wire' {

        BeforeEach {
            Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
            Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
        }

        It 'POSTs object-store-access-policies/rules with names and policy_names and the raw -Attributes body' {
            New-PfbObjectStoreAccessPolicyRule -PolicyName 'full-access-policy' -Name 'rule-1' -Attributes @{
                effect    = 'allow'
                actions   = @('s3:GetObject')
                resources = @('*')
            } -Confirm:$false -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Endpoint -eq 'object-store-access-policies/rules' -and
                $QueryParams.Keys.Count -eq 2 -and
                $QueryParams['names'] -eq 'rule-1' -and
                $QueryParams['policy_names'] -eq 'full-access-policy' -and
                $Body.Keys.Count -eq 3 -and
                $Body['effect'] -eq 'allow' -and
                $Body['actions'][0] -eq 's3:GetObject' -and
                $Body['resources'][0] -eq '*'
            }
        }

        It 'binds -PolicyName then -Name positionally' {
            New-PfbObjectStoreAccessPolicyRule 'pol-2' 'rule-2' -Confirm:$false -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $QueryParams['policy_names'] -eq 'pol-2' -and $QueryParams['names'] -eq 'rule-2'
            }
        }

        It 'sends an empty body when -Attributes is omitted' {
            New-PfbObjectStoreAccessPolicyRule -PolicyName 'pol-3' -Name 'rule-3' -Confirm:$false -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly -ParameterFilter {
                $null -ne $Body -and $Body.Keys.Count -eq 0
            }
        }

        # Deliberately no "omit -Name" invocation test: an unbound mandatory parameter can raise
        # an interactive "Supply values for the following parameters" prompt and hang the run.
        # Mandatory-ness is asserted from parameter metadata above instead.

        It 'fires no request under -WhatIf' {
            New-PfbObjectStoreAccessPolicyRule -PolicyName 'pol-5' -Name 'rule-5' -WhatIf -Array $script:fakeArray

            Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
        }
    }

    Context 'the ShouldProcess target' {

        BeforeAll {
            $recordingHost = [PfbRuleRecordingHost]::new()
            $runspace = [runspacefactory]::CreateRunspace($recordingHost)
            $runspace.Open()

            $ps = [powershell]::Create()
            $ps.Runspace = $runspace
            try {
                $null = $ps.AddCommand('Import-Module').AddParameter('Name', $script:manifest).AddParameter('Force', $true)
                $null = $ps.Invoke()
                if ($ps.Streams.Error.Count -gt 0) {
                    throw "Module import failed in the recording runspace: $($ps.Streams.Error[0])"
                }
                $ps.Commands.Clear()
                # Replace the transport inside the module scope so this runspace physically cannot
                # reach a network, even if -WhatIf failed to short-circuit.
                $null = $ps.AddScript(@'
& (Get-Module PureStorageFlashBladePowerShell) {
    function script:Invoke-PfbApiRequest {
        [CmdletBinding()] param($Array, $Method, $Endpoint, $Body, $QueryParams)
        throw 'Invoke-PfbApiRequest was reached under -WhatIf'
    }
}
'@)
                $null = $ps.Invoke()
                if ($ps.Streams.Error.Count -gt 0) {
                    throw "Transport stub install failed: $($ps.Streams.Error[0])"
                }
            }
            finally { $ps.Dispose() }

            $script:recordingHost = $recordingHost
            $script:runspace = $runspace
        }

        AfterAll {
            if ($script:runspace) {
                $script:runspace.Dispose()
                $script:runspace = $null
            }
        }

        It 'names the rule, not the policy' {
            $script:recordingHost.Sink.Lines.Clear()

            $ps = [powershell]::Create()
            $ps.Runspace = $script:runspace
            try {
                $null = $ps.AddCommand('New-PfbObjectStoreAccessPolicyRule').
                    AddParameter('PolicyName', 'pol-6').
                    AddParameter('Name', 'rule-6').
                    AddParameter('Array', $script:fakeArray).
                    AddParameter('WhatIf', $true)
                $null = $ps.Invoke()
                $errorText = if ($ps.Streams.Error.Count -gt 0) { "$($ps.Streams.Error[0])" } else { '' }
            }
            finally { $ps.Dispose() }

            $errorText | Should -BeExactly ''

            $lines = @($script:recordingHost.Sink.Lines)
            $lines.Count | Should -Be 1 -Because 'exactly one WhatIf message is expected; silence would make this assertion vacuous'

            $match = [regex]::Match($lines[0], 'on target "(?<target>.*)"\.\s*$')
            $match.Success | Should -BeTrue -Because 'the recorded host line must be a WhatIf message'
            $match.Groups['target'].Value | Should -BeExactly 'rule-6'
        }
    }
}
