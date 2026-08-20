#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# ShouldProcess WhatIf text is written to the PSHost, not to any redirectable stream, so
# `... -WhatIf 6>&1` / `*>&1` capture nothing and any assertion built on that is vacuous.
# These tests therefore run the cmdlets in a private runspace whose host records every UI
# write, which is the only mechanism that observes the real target string. It behaves
# identically on Windows PowerShell 5.1 and PowerShell 7.

class PfbRecordingRawUI : System.Management.Automation.Host.PSHostRawUserInterface {
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
    [string] get_WindowTitle() { return 'PfbRecordingHost' }
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

class PfbRecordingUI : System.Management.Automation.Host.PSHostUserInterface {
    [System.Collections.Generic.List[string]]$Lines = [System.Collections.Generic.List[string]]::new()
    [PfbRecordingRawUI]$Raw = [PfbRecordingRawUI]::new()

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
        # instead of hanging or erroring. The answer is always "No" -- nothing must reach the wire.
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

class PfbRecordingHost : System.Management.Automation.Host.PSHost {
    # Named Sink, not UI: a field differing from the PSHost.UI property only in casing is
    # rejected as non-CLS-compliant when the runspace opens.
    [PfbRecordingUI]$Sink = [PfbRecordingUI]::new()
    [guid]$Id = [guid]::NewGuid()

    [string] get_Name() { return 'PfbRecordingHost' }
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

Describe 'Array connection ShouldProcess target truthfulness' {

    BeforeAll {
        function Get-PfbTargetRecorder {
            param([Parameter(Mandatory)][string]$Manifest)

            $recordingHost = [PfbRecordingHost]::new()
            $runspace = [runspacefactory]::CreateRunspace($recordingHost)
            $runspace.Open()

            $ps = [powershell]::Create()
            $ps.Runspace = $runspace
            try {
                $null = $ps.AddCommand('Import-Module').AddParameter('Name', $Manifest).AddParameter('Force', $true)
                $null = $ps.Invoke()
                if ($ps.Streams.Error.Count -gt 0) {
                    throw "Module import failed in the recording runspace: $($ps.Streams.Error[0])"
                }
            }
            finally { $ps.Dispose() }

            return [PSCustomObject]@{ RecordingHost = $recordingHost; Runspace = $runspace }
        }

        function Get-PfbWhatIfTarget {
            <#
                Invokes one cmdlet with -WhatIf inside the recording runspace and returns the target
                string the host was actually asked to display. Throws if the cmdlet errored or if the
                host recorded anything other than exactly one recognisable WhatIf line -- silence would
                otherwise let this assertion pass vacuously.
            #>
            param(
                [Parameter(Mandatory)]$Recorder,
                [Parameter(Mandatory)][string]$Command,
                [Parameter(Mandatory)][hashtable]$Parameters
            )

            $Recorder.RecordingHost.Sink.Lines.Clear()
            $ps = [powershell]::Create()
            $ps.Runspace = $Recorder.Runspace
            try {
                $null = $ps.AddCommand($Command)
                foreach ($key in $Parameters.Keys) { $null = $ps.AddParameter($key, $Parameters[$key]) }
                $null = $ps.AddParameter('WhatIf', $true)
                $null = $ps.Invoke()
                if ($ps.Streams.Error.Count -gt 0) {
                    throw "$Command errored under -WhatIf: $($ps.Streams.Error[0])"
                }
            }
            finally { $ps.Dispose() }

            $lines = @($Recorder.RecordingHost.Sink.Lines)
            if ($lines.Count -ne 1) {
                throw "Expected exactly one host line from $Command -WhatIf, recorded $($lines.Count): $($lines -join ' | ')"
            }
            $match = [regex]::Match($lines[0], 'on target "(?<target>.*)"\.\s*$')
            if (-not $match.Success) {
                throw "Recorded host line is not a WhatIf message: $($lines[0])"
            }
            return $match.Groups['target'].Value
        }

        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $manifest = Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1'
        . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
        $null = Import-PfbTestModule

        # The recording runspace runs the real Assert-PfbConnection, which is satisfied by any
        # object carrying an AuthToken -- no mock and no network access is involved, and -WhatIf
        # short-circuits before Invoke-PfbApiRequest is ever reached.
        $script:recorder = Get-PfbTargetRecorder -Manifest $manifest
        $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
    }

    AfterAll {
        if ($script:recorder) {
            $script:recorder.Runspace.Dispose()
            $script:recorder = $null
        }
    }

    Context 'the recording mechanism itself' {
        It 'observes a WhatIf target that a redirected stream cannot see' {
            # Guard against the whole suite passing vacuously: prove the host really records a
            # target, and prove that the obvious alternative -- merging every stream -- sees no
            # WhatIf text at all, so an assertion built on it could never observe a wrong target.
            Get-PfbWhatIfTarget -Recorder $script:recorder -Command 'Remove-PfbArrayConnection' `
                -Parameters @{ RemoteName = 'FB-B'; Array = $script:fakeArray } | Should -Be 'FB-B'

            $merged = @(Remove-PfbArrayConnection -RemoteName 'FB-B' -WhatIf -Array $script:fakeArray *>&1)
            @($merged | Where-Object { "$_" -like 'What if:*' }).Count |
                Should -Be 0 -Because 'WhatIf text is host-only, so a stream-capture assertion would be vacuous'
        }
    }

    Context 'Remove-PfbArrayConnection' {
        It 'names the connection AND the remote qualifier when -Id and -RemoteId are combined' {
            Get-PfbWhatIfTarget -Recorder $script:recorder -Command 'Remove-PfbArrayConnection' `
                -Parameters @{ Id = 'conn-1'; RemoteId = 'r-77'; Array = $script:fakeArray } |
                Should -BeExactly 'conn-1 (remote r-77)'
        }

        It 'names <Expected> for the single-selector form <Label>' -ForEach @(
            @{ Label = '-RemoteName'; Selector = @{ RemoteName = 'FB-B' }; Expected = 'FB-B' }
            @{ Label = '-Id';         Selector = @{ Id = 'conn-1' };       Expected = 'conn-1' }
            @{ Label = '-RemoteId';   Selector = @{ RemoteId = 'r-77' };   Expected = 'r-77' }
        ) {
            $params = $Selector.Clone()
            $params['Array'] = $script:fakeArray
            Get-PfbWhatIfTarget -Recorder $script:recorder -Command 'Remove-PfbArrayConnection' -Parameters $params |
                Should -BeExactly $Expected
        }
    }

    Context 'Update-PfbArrayConnection' {
        It 'names the connection AND the remote qualifier when -Id and -RemoteId are combined' {
            Get-PfbWhatIfTarget -Recorder $script:recorder -Command 'Update-PfbArrayConnection' `
                -Parameters @{ Id = 'conn-1'; RemoteId = 'r-77'; Array = $script:fakeArray
                               Attributes = @{ management_address = '10.0.2.101' } } |
                Should -BeExactly 'conn-1 (remote r-77)'
        }

        It 'names <Expected> for the single-selector form <Label>' -ForEach @(
            @{ Label = '-RemoteName'; Selector = @{ RemoteName = 'FB-B' }; Expected = 'FB-B' }
            @{ Label = '-Id';         Selector = @{ Id = 'conn-1' };       Expected = 'conn-1' }
            @{ Label = '-RemoteId';   Selector = @{ RemoteId = 'r-77' };   Expected = 'r-77' }
        ) {
            $params = $Selector.Clone()
            $params['Array'] = $script:fakeArray
            $params['Attributes'] = @{ management_address = '10.0.2.101' }
            Get-PfbWhatIfTarget -Recorder $script:recorder -Command 'Update-PfbArrayConnection' -Parameters $params |
                Should -BeExactly $Expected
        }
    }
}
