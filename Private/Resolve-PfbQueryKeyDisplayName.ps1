function Resolve-PfbQueryKeyDisplayName {
    <#
    .SYNOPSIS
        Renders a wire query key as the caller's own parameter name where the cmdlet's metadata
        confirms one, and as the quoted wire key otherwise.
    .DESCRIPTION
        Issue #126. The empty-pipeline diagnostic has to tell a caller which of the things they
        typed was discarded, but $QueryParams carries BUILT wire keys with no parameter
        provenance, so the parameter name has to be recovered.

        snake_case -> PascalCase is a guess. Checking it against
        $Caller.MyInvocation.MyCommand.Parameters is what stops it being one, and the fallback is
        not theoretical: Get-PfbFileSystemSession writes 'protocols' from a parameter named
        -Protocol (singular), so the derived 'Protocols' is not a parameter of that cmdlet and the
        wire key is what gets shown.

        A literal "-Name/-Id/-Filter" message would be wrong for a wider class still. The #90
        specialized-selector cmdlets have no -Name or -Id at all -- Get-PfbNetworkInterfaceNeighbor
        has -LocalPortName, Get-PfbRealmDefaults has -RealmName -- and
        Tests/PfbSpecializedSelectorKeys.Tests.ps1 asserts their absence.
    .PARAMETER Caller
        The public cmdlet's $PSCmdlet. Its MyCommand.Parameters is the authority consulted.
    .PARAMETER WireName
        The built query key, lowercase snake_case.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Caller,

        [Parameter(Mandatory)]
        [string]$WireName
    )

    $candidate = -join @(($WireName -split '_') | ForEach-Object {
            if ($_.Length -eq 0) { '' }
            else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }
        })

    $parameters = $Caller.MyInvocation.MyCommand.Parameters
    if ($null -ne $parameters -and $parameters.ContainsKey($candidate)) { return "-$candidate" }

    return "'$WireName'"
}
