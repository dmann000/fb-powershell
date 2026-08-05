function Invoke-PfbInContext {
    <#
    .SYNOPSIS
        Runs a scriptblock with an ambient, block-scoped Fusion context.
    .DESCRIPTION
        Nesting works with no explicit stack: each invocation captures its own $previous, so
        the call stack provides push/pop discipline and an inner block restores the OUTER
        value rather than clearing it. Exception-safe at every nesting level via finally.

        -Context @() is the deliberate "run this one call locally" escape hatch, and is what
        unblocks an endpoint that does not support context_names while a session default is
        set. It is DISTINCT from no context at all.

        Non-pipeable by design: its pipeline payload would have to be the scriptblock, which
        no cmdlet emits. The blessed form is
        -Context (Get-PfbFleetMember -FleetName 'x').member.name
    .NOTES
        Concurrency: .ContextOverride lives on the shared connection object, so concurrent
        workers pushing overrides on the SAME connection race. Set the context before forking
        parallel work; do not push ambient overrides from inside concurrent workers.
    #>
    [CmdletBinding()]
    param(
        # None of the three is [Parameter(Mandatory)]: a mandatory parameter prompts and hangs
        # under -NonInteractive. Each is checked explicitly below instead.
        [Parameter()]
        [PSCustomObject]$Array,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Context,

        [Parameter(Position = 0)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateSet('Array', 'Fleet', 'TopologyGroup')]
        [string]$Kind = 'Array',

        [Parameter()]
        [switch]$AllArrays
    )

    if (-not $Array)      { throw "Invoke-PfbInContext requires -Array: pass a connection object from Connect-PfbArray." }
    if (-not $ScriptBlock) { throw "Invoke-PfbInContext requires -ScriptBlock: pass the block to run in the context." }
    # -ne $null, never truthiness: @() is falsy but meaningful.
    if ($null -eq $Context) { throw "Invoke-PfbInContext requires -Context. Pass @() to run the block against the local array." }

    $form = Resolve-PfbContextForm -AllArrays:$AllArrays
    # @(...) around the call is load-bearing for the -Context @() escape hatch: a command that
    # emits nothing assigns $null, not an empty array, which would then be rejected downstream.
    $entries = @(ConvertTo-PfbContextEntryList -Name $Context -Kind $Kind -Form $form)
    foreach ($entry in $entries) { Assert-PfbContextEntryComposition -Entry $entry }

    # Deliberately mutated IN PLACE on the shared connection, unlike Set-PfbContext's
    # copy-on-write: the override is ambient, so a copy no caller holds would be invisible.
    $previous = $Array.ContextOverride
    # The [object[]] cast is load-bearing for the -Context @() escape hatch: passing an empty
    # array through as a bare variable makes the binder see $null and reject the mandatory
    # -Entries, in spite of its [AllowEmptyCollection()]. The cast preserves the empty
    # collection. Measured on both PowerShell editions.
    $Array.ContextOverride = New-PfbContext -Entries ([object[]]$entries)
    try     { & $ScriptBlock }
    finally { $Array.ContextOverride = $previous }
}
