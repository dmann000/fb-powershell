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
        map, an empty generatedFrom, or an unparseable version string. "Nothing to check
        against" must never become a warning, exactly as it never becomes a hard failure in
        Get-PfbCapabilityMap.
    .PARAMETER NegotiatedVersion
        The REST version Connect-PfbArray negotiated with the array, e.g. '2.28'.
    .PARAMETER CapabilityMap
        The parsed capability map, or $null when it could not be loaded.
    .OUTPUTS
        [bool]
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$NegotiatedVersion,

        [AllowNull()]
        $CapabilityMap
    )

    if ($null -eq $CapabilityMap) { return $false }

    $scanned = @($CapabilityMap.generatedFrom)
    if ($scanned.Count -eq 0) { return $false }

    # Both helpers cast their split parts with [int] and do not guard the input, so a
    # malformed version string throws rather than returning a verdict. Per the policy above
    # that must be silence, not a warning and not a failed Connect-PfbArray.
    try {
        $highestScanned = (ConvertTo-PfbVersionObject -Versions $scanned)[0].Version

        # "At least" is >=, and an exact match must NOT warn. So the question is whether the
        # map fails to reach the array: NOT (highest >= negotiated).
        return -not (Test-PfbVersionAtLeast -Have $highestScanned -Need $NegotiatedVersion)
    }
    catch {
        Write-Verbose "Test-PfbCapabilityMapCoverage: could not compare '$NegotiatedVersion' against the map's generatedFrom ($($scanned -join ', ')): $($_.Exception.Message)"
        return $false
    }
}
