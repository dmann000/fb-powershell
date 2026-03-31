function Remove-PfbFleetMember {
    <#
    .SYNOPSIS
        Removes a member from a fleet on a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbFleetMember cmdlet removes an array from a fleet on the connected Pure
        Storage FlashBlade. Both the fleet name and member name must be specified. This cmdlet
        has a high confirm impact and will prompt for confirmation by default.
    .PARAMETER FleetName
        The fleet name to remove the member from.
    .PARAMETER MemberName
        The member array name to remove from the fleet.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbFleetMember -FleetName "fleet-prod" -MemberName "array-dc2"

        Removes "array-dc2" from "fleet-prod" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbFleetMember -FleetName "fleet-prod" -MemberName "array-old" -Confirm:$false

        Removes the member without prompting.
    .EXAMPLE
        Remove-PfbFleetMember -FleetName "fleet-dr" -MemberName "array-test" -WhatIf

        Shows what would happen without actually removing the member.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    if ($PSCmdlet.ShouldProcess($target, 'Remove fleet member')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'fleets/members' -QueryParams $queryParams
    }
}
