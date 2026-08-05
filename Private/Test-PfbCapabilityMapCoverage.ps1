function Test-PfbCapabilityMapCoverage {
    <#
    .SYNOPSIS
        Does the connected array's negotiated REST version exceed the range the bundled
        capability map was generated from?
    .DESCRIPTION
        The honesty half of Assert-PfbApiCapability's permissive fallback. When the array is
        newer than the map, the module has no evidence either way and deliberately proceeds
        rather than blocking -- a cmdlet caller never chose the negotiated version, so
        refusing a call because the BUNDLED MAP is behind punishes a packaging lag they
        cannot see. Telling them is what makes that trade honest.

        This function contributes POLICY, not arithmetic. The comparison is delegated to
        Test-PfbVersionAtLeast -- the same comparator Assert-PfbApiCapability uses -- so the
        warning and the capability check can never disagree about what is in range. Finding
        the highest scanned version is delegated to ConvertTo-PfbVersionObject, which
        returns its results sorted Major,Minor DESCENDING, so element [0] is the maximum.
        Do not reimplement either; a naive string compare ranks '2.9' above '2.26', a bug
        already found twice in this repo.

        The policy: return $false whenever the answer cannot be established -- a missing
        map, a generatedFrom that is absent/null/empty, or an unparseable version string.
        "Nothing to check against" must never become a warning, exactly as it never becomes a
        hard failure in Get-PfbCapabilityMap.

        Note which guard catches what: the .Count check below only short-circuits a literal
        empty array. An ABSENT or $null generatedFrom becomes @($null), whose Count is 1, so
        it falls through to the try and is caught there. Both routes return $false; the
        guards are defence in depth rather than the only cover, and neither is individually
        load-bearing.

        -HighestScanned exists so the CALLER never has to re-parse. The warning text needs
        the maximum, and computing it a second time at the call site would put an unguarded
        copy of this function's own throwing expression outside this try/catch -- safe only
        by an invariant living in a different file. Handing it back keeps one parse, inside
        one guard. This mirrors Assert-PfbConnection's existing [ref] idiom.
    .PARAMETER NegotiatedVersion
        The REST version Connect-PfbArray negotiated with the array, e.g. '2.28'.
    .PARAMETER CapabilityMap
        The parsed capability map, or $null when it could not be loaded.
    .PARAMETER HighestScanned
        Optional [ref]. Receives the highest version in generatedFrom when that could be
        determined. Only meaningful when this function returns $true; left untouched
        otherwise.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$NegotiatedVersion,

        [AllowNull()]
        $CapabilityMap,

        [AllowNull()]
        [ref]$HighestScanned
    )

    if ($null -eq $CapabilityMap) { return $false }

    $scanned = @($CapabilityMap.generatedFrom)
    if ($scanned.Count -eq 0) { return $false }

    # Both helpers cast their split parts with [int] and do not guard the input, so a
    # malformed version string throws rather than returning a verdict. Per the policy above
    # that must be silence, not a warning and not a failed Connect-PfbArray.
    try {
        $highest = (ConvertTo-PfbVersionObject -Versions $scanned)[0].Version

        # "At least" is >=, and an exact match must NOT warn. So the question is whether the
        # map fails to reach the array: NOT (highest >= negotiated).
        $exceeds = -not (Test-PfbVersionAtLeast -Have $highest -Need $NegotiatedVersion)

        # Publish the max only once the comparison has succeeded, so the caller can never
        # read a value produced by a half-completed parse.
        if ($exceeds -and $null -ne $HighestScanned) { $HighestScanned.Value = $highest }
        return $exceeds
    }
    catch {
        Write-Verbose "Test-PfbCapabilityMapCoverage: could not compare '$NegotiatedVersion' against the map's generatedFrom ($($scanned -join ', ')): $($_.Exception.Message)"
        return $false
    }
}
