function Assert-PfbApiCapability {
    <#
    .SYNOPSIS
        Throws before an API call is sent if the connected array's REST version does not
        support the requested endpoint, query parameter, or request-body field.
    .DESCRIPTION
        Looks up Data/PfbCapabilityMap.json (built by tools/Build-PfbCapabilityMap.ps1) for
        the "$Method $Endpoint" being called. If the map is unavailable, or the endpoint is
        not present in it, this is a deliberate no-op: the map may be stale, or the endpoint
        may take path parameters not captured by the map's flat key format. A capability
        check must never be the reason a call that would otherwise succeed gets blocked.
    .PARAMETER ApiVersion
        Overrides the version to check against instead of $Array.ApiVersion (mirrors
        Invoke-PfbApiRequest's -ApiVersionOverride).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Array,

        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        # Hashtable OR array. Invoke-PfbApiRequest forwards its own -Body straight into this
        # parameter, and a few endpoints declare a top-level JSON array as their request body,
        # so this must admit both or the forwarding call fails at bind time.
        #
        # ICollection, not IEnumerable and not a bare [object]. IEnumerable looks narrower but
        # is worse: System.String implements it, so PowerShell happily converts -Body 42 into
        # the string "42" instead of rejecting it. ICollection admits every dictionary and
        # list shape (Hashtable, Hashtable[], Object[], OrderedDictionary, List<T>) while
        # still rejecting strings, numbers, booleans and PSCustomObjects exactly as
        # [hashtable] did, and -- unlike a ValidateScript, which rejects an explicit $null
        # even under [AllowNull()] -- it still accepts the $null this function is handed on
        # every bodyless call. Verified under both PowerShell 5.1 and 7.
        # See the array-body note on the body-field loop below for how each shape is treated.
        [Parameter()]
        [System.Collections.ICollection]$Body,

        [Parameter()]
        [hashtable]$QueryParams,

        [Parameter()]
        [string]$ApiVersion
    )

    $map = Get-PfbCapabilityMap
    if (-not $map) { return }

    $key = Get-PfbEndpointKey -Method $Method -Endpoint $Endpoint
    $entry = $map.endpoints.$key
    if (-not $entry) { return }

    $effectiveVersion = if ($ApiVersion) { $ApiVersion } else { $Array.ApiVersion }
    if (-not $effectiveVersion) { return }

    $versionMap = Get-PfbVersionMap

    function Format-PfbVersionDescription {
        param([string]$RestVersion)
        $purity = $versionMap.$RestVersion.purity
        if ($purity) { return "REST $RestVersion (Purity//FB $purity)" }
        return "REST $RestVersion"
    }

    $violations = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-PfbVersionAtLeast -Have $effectiveVersion -Need $entry.minVersion)) {
        $violations.Add("$key requires $(Format-PfbVersionDescription $entry.minVersion)")
    }

    if ($QueryParams) {
        foreach ($paramName in $QueryParams.Keys) {
            $value = $QueryParams[$paramName]
            if ($null -eq $value -or ($value -is [string] -and [string]::IsNullOrEmpty($value))) { continue }

            $introducedIn = $entry.parameters.$paramName
            if ($introducedIn -and -not (Test-PfbVersionAtLeast -Have $effectiveVersion -Need $introducedIn)) {
                $violations.Add("parameter '$paramName' on $key requires $(Format-PfbVersionDescription $introducedIn)")
            }
        }
    }

    # Dictionary bodies only. An array body's per-element fields are NOT checked -- but note
    # the reason has changed, and the note this comment used to carry was wrong about what
    # would happen next.
    #
    # It previously read that array-bodied endpoints carry "bodyProperties": {} in
    # Data/PfbCapabilityMap.json, because Get-PfbSchemaPropertyNames' walk resolves $ref and
    # allOf but never descends an array schema's "items" -- so a check would compare every
    # field against an empty map and could never fire. That was true, and it concluded that
    # "this loop picks it up for free if a future map representation ever lands."
    #
    # That map representation has now landed (issue #82): Get-PfbSpecCapabilities hops "items"
    # at its call site, and PUT /workloads/tags/batch, POST /nodes/batch,
    # POST /resource-accesses/batch and POST /fleets/members/batch now carry real per-element
    # fields. But it is NOT picked up for free, because of the type guard on the line below:
    # an array body arrives as [hashtable[]] (see Set-PfbWorkloadTag, which passes its -Tags
    # straight through), and [hashtable[]] is not an IDictionary, so this loop is skipped
    # before the map is ever consulted.
    #
    # Enabling it therefore means relaxing this guard to iterate the elements and union their
    # keys -- a deliberate behaviour change that can start refusing calls that succeed today,
    # not a no-op. It is left as its own change rather than smuggled in with the map fix.
    # Today the blast radius is nil: Set-PfbWorkloadTag is the only cmdlet reaching an
    # array-bodied endpoint, and all five of its fields are 2.23 -- but that stops being true
    # as soon as #44 adds cmdlets for the other three.
    #
    # Endpoint minVersion and query-parameter checks above still run for array-bodied calls,
    # which is gating those endpoints previously had none of.
    if ($Body -is [System.Collections.IDictionary]) {
        foreach ($propName in $Body.Keys) {
            $introducedIn = $entry.bodyProperties.$propName
            if ($introducedIn -and -not (Test-PfbVersionAtLeast -Have $effectiveVersion -Need $introducedIn)) {
                $violations.Add("request-body field '$propName' on $key requires $(Format-PfbVersionDescription $introducedIn)")
            }
        }
    }

    if ($violations.Count -eq 0) { return }

    $haveDescription = Format-PfbVersionDescription $effectiveVersion
    throw "$($violations -join '; '), but the connected array is running $haveDescription. Upgrade the array or omit the unsupported option(s)."
}
