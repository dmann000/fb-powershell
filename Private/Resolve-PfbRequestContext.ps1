function Resolve-PfbRequestContext {
    <#
    .SYNOPSIS
        Resolves the effective Fusion context for one request, once, at the choke point.
    .DESCRIPTION
        Precedence:
            explicit -QueryParams['context_names']  >  ContextOverride  >  DefaultContext  >  none

        TRI-STATE. $null means UNSET. A context whose Entries collection is EMPTY means the
        caller explicitly asked for no context ("run this one call locally"). Both inject
        nothing, but only the unset form may fall through to a lower precedence tier, and only
        a NON-EMPTY resolved context is subject to the hard-throw gates. Every test here is
        written with -ne $null rather than truthiness for exactly that reason.

        The explicit -QueryParams tier is defensive layering: nothing in the public surface
        can populate it today (resolved open question 1).
    .OUTPUTS
        A PfbContext object, or $null when unset.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Array,
        [Parameter()][AllowNull()][hashtable]$QueryParams
    )

    if ($QueryParams -and $QueryParams.ContainsKey($script:PfbContextParameterName)) {
        $explicit = $QueryParams[$script:PfbContextParameterName]
        # @(...) around the CALL, not just around $explicit: for an explicitly-empty context
        # ConvertTo-PfbContextEntryList emits nothing, and a command emitting nothing assigns
        # $null -- so the unwrapped form passes $null to -Entries, which throws, and would
        # collapse "explicitly no context" into "unset" if it did not. Measured on both
        # editions in Task 5; New-PfbContext accepts the wrapped empty array fine.
        return New-PfbContext -Entries @(ConvertTo-PfbContextEntryList -Name @($explicit))
    }
    if ($null -ne $Array.ContextOverride) { return $Array.ContextOverride }
    if ($null -ne $Array.DefaultContext)  { return $Array.DefaultContext }
    return $null
}
