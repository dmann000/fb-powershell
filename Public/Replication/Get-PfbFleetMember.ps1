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

    # Decorate with top-level MemberName/FleetName. ValueFromPipelineByPropertyName matches
    # only TOP-LEVEL names, and this endpoint nests the array name at .member.name -- so
    # without this, piping into a context-scoping cmdlet binds nothing and silently no-ops.
    # Additive by design: the raw nested member/fleet objects stay, so existing callers
    # reaching .member.name keep working.
    #
    # Runs per emitted item, so -AutoPaginate's later pages are decorated too.
    #
    # Deliberately no IsLocal: is_local is relative to the CALL'S CONTEXT rather than the
    # connection, so a Where-Object { -not $_.IsLocal } idiom would silently select a
    # different array once a context is active.
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'fleets/members' -QueryParams $queryParams -AutoPaginate |
        ForEach-Object {
            # Invoke-PfbApiRequest returns a bare { total_item_count = N } sentinel -- not a
            # member -- only for a request that explicitly asked for total_only=true. This
            # cmdlet exposes no -TotalOnly parameter and so cannot set that key, which means
            # today's response layer cannot hand this branch a sentinel at all.
            #
            # Kept as defence-in-depth rather than as a live path: if the response layer ever
            # emits one again, decorating it would produce an object that LOOKS like a fleet
            # member whose name is $null, and piping THAT into a context-scoping cmdlet would
            # bind a $null name -- the exact silent-wrong-binding failure this decoration
            # exists to prevent. Pass it through undecorated so the absence of MemberName
            # fails loudly instead.
            if (($_.PSObject.Properties.Name -contains 'total_item_count') -and
                ($_.PSObject.Properties.Name -notcontains 'member')) {
                return $_
            }

            Add-Member -InputObject $_ -MemberType NoteProperty -Name 'MemberName' -Value $_.member.name -Force -PassThru |
                Add-Member -MemberType NoteProperty -Name 'FleetName' -Value $_.fleet.name -Force -PassThru
        }
}
