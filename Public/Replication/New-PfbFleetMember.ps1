function New-PfbFleetMember {
    <#
    .SYNOPSIS
        Adds a member to a fleet on a FlashBlade array.
    .DESCRIPTION
        The New-PfbFleetMember cmdlet adds an array as a member of a fleet on the connected
        Pure Storage FlashBlade. Per the FlashBlade REST API spec, `POST /fleets/members` must
        be called from the array that is joining the fleet, and it identifies the fleet via a
        `fleet_ids`/`fleet_names` query parameter plus a request body carrying the fleet key
        (generated on any array already in the fleet) and a reference to the joining array
        itself.

        There are two ways to supply that body:

        -FleetKey takes the key straight from New-PfbFleetKey and builds the whole body for
        you, resolving the joining array's own id with Get-PfbArray against the connection you
        are already using. This is the common case, because the array running the cmdlet is by
        definition the array that is joining.

        -Members passes the request body through unaltered, for the cases the convenience path
        does not cover -- enrolling several members in one call, or naming a member other than
        the array the connection points at.

        The two are mutually exclusive parameter sets, so the engine rejects supplying both
        rather than having to pick one silently.

        CONFIRMED WIRE-CONTRACT BUG (issue #38): this cmdlet previously sent `fleet_names` and
        `member_names` as bare query parameters with no request body at all. `member_names` is
        not a valid query parameter for this endpoint (only `fleet_ids`/`fleet_names` are, per
        the OpenAPI spec's parameter list for POST /fleets/members) and there was no way to
        supply the required fleet key or self-identification, so this cmdlet could never have
        succeeded against a real array. -MemberName has been removed; -Members and -FleetKey
        are what expose the actual request body.
    .PARAMETER FleetName
        The fleet name to add the member to. Sent as the `fleet_names` query parameter.
    .PARAMETER FleetId
        The fleet ID to add the member to. Sent as the `fleet_ids` query parameter. This is the
        id form of the same fleet selector as -FleetName, and is unrelated to -FleetKey: the
        selector says which fleet, the key authorises the join.
    .PARAMETER FleetKey
        The fleet key generated on an array already in the fleet, as returned by
        New-PfbFleetKey. The joining array's own id is resolved with Get-PfbArray over the same
        connection and the `members` body is built from the two, so this call is issued even
        under -WhatIf -- it is a read, and without it there is no body to describe.
    .PARAMETER Members
        Info about the members being added to the fleet, as a hashtable or array of hashtables
        -- for example @{ key = "<fleet key>"; member = @{ id = "<this array's own id>" } }.
        The `key` is the fleet key generated on any array already in the fleet; `member` is a
        reference to the array joining the fleet.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        $key = New-PfbFleetKey -Array $existingMember
        New-PfbFleetMember -FleetName "fleet-prod" -FleetKey $key.fleet_key -Array $joiningArray

        Joins $joiningArray to "fleet-prod". The joining array identifies itself, so only the
        fleet and the key have to be supplied.
    .EXAMPLE
        New-PfbFleetMember -FleetName "fleet-prod" -Members @{ key = "1fc6297a-5183-4b7a-8d58-0182af1a2b64"; member = @{ id = "10314f42-020d-7080-8013-000ddt400012" } }

        Adds a member by explicit id, for the cases -FleetKey does not cover.
    .EXAMPLE
        New-PfbFleetMember -FleetId "10314f42-020d-7080-8013-000ddt400099" -Members @{ key = "key-456"; member = @{ id = "this-array-id" } } -WhatIf

        Shows what would happen without actually adding the member, identifying the fleet by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Members')]
    param(
        [Parameter()] [string]$FleetName,
        [Parameter()] [string]$FleetId,
        [Parameter(Mandatory, ParameterSetName = 'FleetKey')] [string]$FleetKey,
        [Parameter(ParameterSetName = 'Members')] [hashtable[]]$Members,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('FleetName')) { $queryParams['fleet_names'] = $FleetName }
    if ($PSBoundParameters.ContainsKey('FleetId'))   { $queryParams['fleet_ids']   = $FleetId }

    # Constraint 8(c): each members[] item is {key, member}, where `key` is a plain string
    # outside {id, name, resource_type} -- this makes the array COMPOSITE, not an array of
    # references, so it is passed straight through rather than projected into @{ name = ... }.
    $body = @{}
    $self = $null

    if ($PSCmdlet.ParameterSetName -eq 'FleetKey') {
        $self = Get-PfbArray -Array $Array | Select-Object -First 1
        if (-not $self -or -not $self.id) {
            throw ("Could not determine this array's own id from Get-PfbArray, so the fleet " +
                   'member body cannot be built. Supply the member reference explicitly with ' +
                   '-Members instead.')
        }
        $body['members'] = @(@{ key = $FleetKey; member = @{ id = $self.id } })
    }
    elseif ($PSBoundParameters.ContainsKey('Members')) {
        $body['members'] = @($Members)
    }

    $fleet  = if ($FleetName) { $FleetName } elseif ($FleetId) { $FleetId } else { 'fleet member' }
    $target = if ($self -and $self.name) { "$($self.name) into $fleet" } else { $fleet }

    if ($PSCmdlet.ShouldProcess($target, 'Add fleet member')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'fleets/members' -Body $body -QueryParams $queryParams
    }
}
