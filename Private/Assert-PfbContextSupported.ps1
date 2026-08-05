function Get-PfbEndpointKey {
    <#
    .SYNOPSIS
        Builds the capability-map endpoints key for a method and endpoint.
    .DESCRIPTION
        ONE home for this normalization. Assert-PfbApiCapability and the context gates must
        agree byte-for-byte: a second copy that differed by a leading slash would miss every
        entry in the map. That failure is silent, which makes it worse than a throw --
        Assert-PfbApiCapability treats a missing entry as a deliberate pass
        ("if (-not $entry) { return }"), so a drifted key blocks nothing. It quietly
        disables the version gate for every endpoint in the module.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint
    )

    "$Method /" + $Endpoint.TrimStart('/')
}
