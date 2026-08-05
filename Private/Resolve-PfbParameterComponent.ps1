function Resolve-PfbParameterComponent {
    <#
    .SYNOPSIS
        Resolves which OpenAPI component backs a named parameter on one capability-map
        endpoint entry, per the map's three-step resolution contract.
    .DESCRIPTION
        THE single runtime home of the contract documented in
        tools/Build-PfbCapabilityMap.ps1's second pass. Three ordered steps:

          1. If the endpoint's parameterComponentOverrides CONTAINS THE KEY for this
             parameter, that value is authoritative -- EVEN WHEN IT IS JSON null, which
             means "this endpoint's parameter has no component". Defaults are not consulted.
          2. Otherwise, if the map's top-level parameterComponentDefaults contains the
             parameter name, use that.
          3. Otherwise, there is no known component.

        WHY THIS IS ITS OWN FUNCTION. Steps 1-with-null and 3 both return $null, so the
        distinction is NOT observable in the return value -- it is entirely about whether
        step 2 is allowed to run. An implementation that tests the override's VALUE
        (`if ($overrides.$name)`) rather than the KEY's PRESENCE silently falls through to
        the default for a null override, yielding a component name the endpoint does not
        actually have. Only 7 of 4109 parameter declarations in fb2.27 are inline/no-$ref,
        so a wrong implementation is right almost everywhere -- and wrong precisely on the
        endpoints the Fusion cardinality rule (Test-PfbContextMultiValueCapable) depends on.

        Extracted from tools/lib/PfbContextRuleTools.ps1 per issue #74: the module could not
        feed its own declared cardinality rule, because the code producing the rule's
        -ContextComponent input lived in tools/, which the module never loads. tools/ may
        depend on Private/; never the reverse.

        Deliberately parameterised on -ParameterName rather than hardcoded to
        'context_names': the contract is a property of the capability map's shape, not of
        Fusion, and allow_errors needs the same resolution in Phase 2.

        PURE -- no map loading, no file I/O. The caller supplies the entry and the defaults
        table, exactly like Test-PfbContextMultiValueCapable.
    .PARAMETER EndpointEntry
        One capability-map endpoints.<key> object, as parsed from
        Data/PfbCapabilityMap.json.
    .PARAMETER ParameterName
        The API parameter name to resolve, e.g. 'context_names'.
    .PARAMETER ParameterComponentDefaults
        The map's top-level parameterComponentDefaults object. Pass $null when unavailable;
        resolution then stops after step 1.
    .OUTPUTS
        [string] the resolved component name, or $null when the endpoint's parameter has no
        component (step 1 with a null override) or no component is known (step 3). These two
        outcomes are deliberately indistinguishable to the caller.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $EndpointEntry,

        [Parameter(Mandatory)]
        [string]$ParameterName,

        [AllowNull()]
        $ParameterComponentDefaults
    )

    # Key PRESENCE, never the value's truthiness -- see .DESCRIPTION. A present key whose
    # value is null returns null here and must NOT reach the defaults lookup below.
    #
    # Both container shapes must be handled, and they need DIFFERENT operators:
    #   * PSCustomObject -- what ConvertFrom-Json yields reading Data/PfbCapabilityMap.json.
    #   * IDictionary ([ordered]@{}) -- what tools/Build-PfbCapabilityMap.ps1 builds IN
    #     MEMORY before serializing, so any tools/ caller resolving against the map it just
    #     built passes this shape.
    # For a Hashtable/OrderedDictionary, .PSObject.Properties.Name does NOT return the keys
    # -- it returns the adapted CLR surface (Keys, Values, Count, IsReadOnly, ...). A
    # presence test written only against .PSObject.Properties.Name is therefore ALWAYS FALSE
    # for dictionary input and silently falls through to the defaults, reproducing the exact
    # wrong-component defect this function exists to prevent. It is also a false POSITIVE
    # for an intrinsic name ('Count' would "resolve" to the item count).
    #
    # Empty containers are covered by key absence, not truthiness: an empty PSCustomObject
    # AND an empty hashtable are both truthy, so truthiness carries no information here.
    $overrides = $EndpointEntry.parameterComponentOverrides
    if ($null -ne $overrides) {
        if ($overrides -is [System.Collections.IDictionary]) {
            if ($overrides.Contains($ParameterName)) { return $overrides[$ParameterName] }
        }
        elseif ($overrides.PSObject.Properties.Name -contains $ParameterName) {
            return $overrides.$ParameterName
        }
    }

    if ($null -ne $ParameterComponentDefaults) {
        if ($ParameterComponentDefaults -is [System.Collections.IDictionary]) {
            if ($ParameterComponentDefaults.Contains($ParameterName)) {
                return $ParameterComponentDefaults[$ParameterName]
            }
        }
        elseif ($ParameterComponentDefaults.PSObject.Properties.Name -contains $ParameterName) {
            return $ParameterComponentDefaults.$ParameterName
        }
    }

    return $null
}
