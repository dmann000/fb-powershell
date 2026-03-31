function New-PfbFleetMember {
    <#
    .SYNOPSIS
        Adds a member to a fleet on a FlashBlade array.
    .DESCRIPTION
        The New-PfbFleetMember cmdlet adds an array as a member of a fleet on the connected
        Pure Storage FlashBlade. Both the fleet name and the member name must be specified.
    .PARAMETER FleetName
        The fleet name to add the member to.
    .PARAMETER MemberName
        The member array name to add to the fleet.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbFleetMember -FleetName "fleet-prod" -MemberName "array-dc2"

        Adds "array-dc2" as a member of "fleet-prod".
    .EXAMPLE
        New-PfbFleetMember -FleetName "fleet-dr" -MemberName "array-dc3" -WhatIf

        Shows what would happen without actually adding the member.
    .EXAMPLE
        New-PfbFleetMember -FleetName "fleet-prod" -MemberName "array-dc4" -Confirm:$false

        Adds the member without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string]$FleetName,
        [Parameter(Mandatory)] [string]$MemberName,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    $queryParams['fleet_names'] = $FleetName
    $queryParams['member_names'] = $MemberName

    $target = "${FleetName}:${MemberName}"

    if ($PSCmdlet.ShouldProcess($target, 'Add fleet member')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fleets/members' -QueryParams $queryParams
    }
}
