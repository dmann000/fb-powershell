function Get-PfbFleetMember {
    <#
    .SYNOPSIS
        Retrieves fleet member associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbFleetMember cmdlet returns fleet member relationships from the connected
        Pure Storage FlashBlade. Fleet members are arrays that belong to a fleet. Results
        can be filtered by fleet name, member name, or a server-side filter expression.
    .PARAMETER FleetName
        One or more fleet names to filter by.
    .PARAMETER MemberName
        One or more member names to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "fleet.name" or "member.name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbFleetMember

        Retrieves all fleet members from the connected FlashBlade.
    .EXAMPLE
        Get-PfbFleetMember -FleetName "fleet-prod"

        Retrieves all members of the fleet named "fleet-prod".
    .EXAMPLE
        Get-PfbFleetMember -FleetName "fleet-prod" -MemberName "array-dc2"

        Retrieves the specific fleet member association.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$FleetName,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    if ($FleetName) { $queryParams['fleet_names'] = $FleetName -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'fleets/members' -QueryParams $queryParams -AutoPaginate
}
