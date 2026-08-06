function Set-PfbContext {
    <#
    .SYNOPSIS
        Sets the durable Fusion context on a connection, returning a NEW connection object.
    .DESCRIPTION
        Copy-on-write: the caller's connection is never mutated, so a helper frame, an outer
        scope, or a loop iteration holding the old object keeps its original scope. Only the
        caller capturing the return value sees the change. The output IS the effect -- there
        is no -PassThru.

        No network call is made. The context name is not resolved: the wire rejects a bad one
        loudly and verbatim on first use (code 42, quoting the offending value), so validating
        here would buy only failing one call earlier at the cost of a hidden round trip.
        Composition IS validated locally -- see section 9 of the design.
    .NOTES
        Mixed-platform fleets: Get-PfbFleetMember will happily return FlashArrays. Piping
        those in is not supported -- cross-platform context is a non-goal (open question 5).
    .EXAMPLE
        $fb = Get-PfbFleetMember -FleetName 'fleet-prod' | Set-PfbContext
    .EXAMPLE
        $fb = Get-PfbFleet | Set-PfbContext -AllArrays
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        # Ordinary parameter, NOT the pipeline slot: the pipeline belongs to -Context so
        # Get-PfbFleetMember | Set-PfbContext works. Defaults to the current default
        # connection.
        [Parameter()]
        [PSCustomObject]$Array,

        # Deliberately NO [ValidateNotNull()] here, unlike Connect-PfbArray's -Context: this
        # is the ValueFromPipeline slot, and $null | Set-PfbContext must fall through to the
        # friendly explicit throw in end{} rather than surface a raw binding error.
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('MemberName', 'Name')]
        [string[]]$Context,

        [Parameter()]
        [ValidateSet('Array', 'Fleet', 'TopologyGroup')]
        [string]$Kind = 'Array',

        [Parameter()]
        [switch]$AllArrays,

        # Tri-state, reserved for Phase 2. Accepted and stored; nothing is injected for it.
        [Parameter()]
        [switch]$AllowErrors
    )

    begin {
        # Accumulate across process{} and emit ONE connection in end{}. Emitting per-item
        # would yield N connection objects for N piped members, each a copy of the same
        # original -- so N-1 of them silently lose the others' entries.
        $names = [System.Collections.Generic.List[string]]::new()
    }

    process {
        # Truthiness is deliberate, not sloppy: it skips $null AND @() AND a piped empty
        # string, all of which correctly land on the "requires -Context" throw in end{}.
        # $null -ne $Context would instead let '' through and mint an entry with an empty name.
        if ($Context) { foreach ($name in $Context) { $names.Add($name) } }
    }

    end {
        # An explicit throw, not [Parameter(Mandatory)]: a mandatory parameter prompts and
        # hangs under -NonInteractive, which is how CI and every test run invokes this.
        if ($names.Count -eq 0) {
            throw "Set-PfbContext requires -Context (or piped input binding to it). To remove a context, use Clear-PfbContext."
        }

        $target = if ($Array) { $Array } else { $script:PfbDefaultArray }
        if (-not $target) {
            throw "Set-PfbContext requires a connection: pass -Array, or connect first with Connect-PfbArray."
        }

        $form = Resolve-PfbContextForm -AllArrays:$AllArrays
        $entries = ConvertTo-PfbContextEntryList -Name $names.ToArray() -Kind $Kind -Form $form
        foreach ($entry in $entries) { Assert-PfbContextEntryComposition -Entry $entry }

        $allowErrors = if ($PSBoundParameters.ContainsKey('AllowErrors')) { [bool]$AllowErrors } else { $null }

        # Built ONCE, above the gate, and the same object is both gated and stored. An earlier
        # revision passed a throwaway New-PfbContext to the gate and built the real one after,
        # which minted two objects per call and meant the gate never saw -AllowErrors.
        #
        # NOT named $context: PowerShell variable names are case-insensitive, so that is the
        # SAME variable as the [string[]]$Context parameter -- assigning a PfbContext object to
        # it silently COERCES it to a one-element string[], and both the gate and
        # $copy.DefaultContext then receive a stringified array instead of a context. Measured.
        $newContext = New-PfbContext -Entries $entries -AllowErrors $allowErrors

        # A static-model admin cannot use a context at all, so say so here rather than letting
        # every later call fail with an opaque code 20. Fails open on an indeterminate model.
        Assert-PfbContextAuthorizationModel -Array $target -Context $newContext

        $copy = Copy-PfbConnection -Array $target
        $copy.DefaultContext = $newContext
        Update-PfbConnectionCache -Array $copy
        $copy
    }
}
