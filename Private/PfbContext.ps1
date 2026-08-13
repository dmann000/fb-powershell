# The Fusion context object. See docs/design/fusion-context-phase-1-spec.md section 1 for
# why Kind is per-entry and Form is an enum rather than two booleans.

# The Kind/Form vocabularies live only in the ValidateSet literals below (and on the
# public cmdlets that surface them), because ValidateSet cannot take a variable. A
# meta-test in Tests/PfbContext.Tests.ps1 asserts every site agrees.
$script:PfbAllArraysSuffix = '.arrays'   # case-sensitive on the wire; measured

function New-PfbContextEntry {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('Array', 'Fleet', 'TopologyGroup')][string]$Kind = 'Array',
        [ValidateSet('Object', 'AllArrays')][string]$Form = 'Object'
    )
    [PSCustomObject]@{ Name = $Name; Kind = $Kind; Form = $Form }
}

# The single place the -AllArrays switch becomes a Form token. Every public cmdlet surfacing
# context spells Form as a switch rather than a $Form parameter, so without this the mapping
# gets copy-pasted per cmdlet and a third Form value would update some copies and not others --
# the exact drift the ValidateSet meta-test guards for the vocabulary itself. Deliberately NO
# ValidateSet here: it takes a switch, so it adds no site to that scan.
function Resolve-PfbContextForm {
    [CmdletBinding()]
    [OutputType([string])]
    param([switch]$AllArrays)
    if ($AllArrays) { 'AllArrays' } else { 'Object' }
}

function New-PfbContext {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Entries,
        # Tri-state: $null means "not specified". Reserved in Phase 1, surfaced in Phase 2.
        [AllowNull()][object]$AllowErrors = $null
    )
    [PSCustomObject]@{ Entries = @($Entries); AllowErrors = $AllowErrors }
}

function Assert-PfbContextEntryComposition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Entry)

    if ($Entry.Kind -eq 'Array' -and $Entry.Form -eq 'AllArrays') {
        throw "Context '$($Entry.Name)' is an array with -AllArrays, which is not a valid combination: an array has no members. Drop -AllArrays, or name a fleet or topology group instead."
    }
    # Measured on every endpoint probed, including the topology-group endpoints themselves:
    # a bare group name is rejected (code 13 there, code 42 on array-scoped resources). A
    # group is reachable as a context only through <group>.arrays.
    if ($Entry.Kind -eq 'TopologyGroup' -and $Entry.Form -eq 'Object') {
        throw "Context '$($Entry.Name)' is a topology group addressed as an object, which no endpoint accepts. Use -AllArrays to target '<name>.arrays' instead."
    }
}

function ConvertTo-PfbContextWireValue {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)]$Entry)

    Assert-PfbContextEntryComposition -Entry $Entry
    if ($Entry.Form -eq 'AllArrays') { return "$($Entry.Name)$($script:PfbAllArraysSuffix)" }
    return $Entry.Name
}

function ConvertTo-PfbContextEntryList {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Name,
        [ValidateSet('Array', 'Fleet', 'TopologyGroup')][string]$Kind = 'Array',
        [ValidateSet('Object', 'AllArrays')][string]$Form = 'Object'
    )
    @($Name | ForEach-Object { New-PfbContextEntry -Name $_ -Kind $Kind -Form $Form })
}
