function New-PfbObjectStoreAccountExport {
    <#
    .SYNOPSIS
        Creates a new object store account export on the FlashBlade.
    .DESCRIPTION
        Creates an object store account export, associating an object store
        account member with an S3 export policy and the server that hosts the
        export.

        The POST endpoint identifies its targets with `member_names`/`member_ids`
        and `policy_names`/`policy_ids`; it accepts neither `names` nor `ids`.
        The request body requires a `server` reference, supplied here through
        -ServerName or -ServerId.

        The individual typed parameters and the raw -Attributes hashtable are
        mutually exclusive: they live in separate parameter sets, so PowerShell
        rejects a mixed invocation at bind time rather than letting -Attributes
        silently override an explicitly supplied value.
    .PARAMETER MemberName
        One or more object store account member names to export (`member_names`).
    .PARAMETER MemberId
        One or more object store account member IDs to export (`member_ids`).
    .PARAMETER PolicyName
        One or more S3 export policy names (`policy_names`). Mutually exclusive
        with -PolicyId.
    .PARAMETER PolicyId
        One or more S3 export policy IDs (`policy_ids`). Mutually exclusive with
        -PolicyName.
    .PARAMETER ServerName
        The name of the server that hosts the export. Builds the required
        `server` body reference. Mutually exclusive with -ServerId.
    .PARAMETER ServerId
        The ID of the server that hosts the export. Builds the required `server`
        body reference. Mutually exclusive with -ServerName.
    .PARAMETER ExportEnabled
        If set to `true`, the account export is enabled. Omit to let the array
        apply its default (`true`).
    .PARAMETER Attributes
        A raw hashtable body. Mutually exclusive with the individual typed body
        parameters above; the caller is responsible for supplying the required
        `server` reference.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccountExport -MemberName "acct1" -PolicyName "s3-export-policy" -ServerName "server1"

        Creates an export of object store account "acct1" through the S3 export
        policy "s3-export-policy" on "server1".
    .EXAMPLE
        New-PfbObjectStoreAccountExport -MemberId "10314f42-020d-7080-8013-000ddt400090" -PolicyId "20314f42-020d-7080-8013-000ddt400091" -ServerId "30314f42-020d-7080-8013-000ddt400092"

        Creates the same export identifying the member, policy, and server by ID.
    .EXAMPLE
        New-PfbObjectStoreAccountExport -MemberName "acct1" -PolicyName "s3-export-policy" -ServerName "server1" -ExportEnabled:$false

        Creates the export in a disabled state.
    .EXAMPLE
        New-PfbObjectStoreAccountExport -MemberName "acct1" -PolicyName "s3-export-policy" -Attributes @{
            server         = @{ name = "server1" }
            export_enabled = $true
        }

        Creates the export from a hand-rolled body.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByMemberNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByMemberNameIndividual', Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'ByMemberNameAttributes',  Mandatory, Position = 0)]
        [string[]]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByMemberIdAttributes',  Mandatory)]
        [string[]]$MemberId,

        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,

        [Parameter(ParameterSetName = 'ByMemberNameIndividual')]
        [Parameter(ParameterSetName = 'ByMemberIdIndividual')]
        [string]$ServerName,

        [Parameter(ParameterSetName = 'ByMemberNameIndividual')]
        [Parameter(ParameterSetName = 'ByMemberIdIndividual')]
        [string]$ServerId,

        [Parameter(ParameterSetName = 'ByMemberNameIndividual')]
        [Parameter(ParameterSetName = 'ByMemberIdIndividual')]
        [Nullable[bool]]$ExportEnabled,

        [Parameter(ParameterSetName = 'ByMemberNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByMemberIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSBoundParameters.ContainsKey('PolicyName') -and $PSBoundParameters.ContainsKey('PolicyId')) {
        throw 'Specify either -PolicyName or -PolicyId, not both.'
    }

    # POST accepts member_names/member_ids and policy_names/policy_ids only --
    # neither 'names' nor 'ids' is declared on this method, which is why the
    # query hashtable is built here instead of through Add-PfbCommonQueryParams
    # (that helper hardcodes the generic 'names'/'ids' keys).
    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('MemberName')) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($PSBoundParameters.ContainsKey('MemberId'))   { $queryParams['member_ids']   = $MemberId   -join ',' }
    if ($PSBoundParameters.ContainsKey('PolicyName')) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PSBoundParameters.ContainsKey('PolicyId'))   { $queryParams['policy_ids']   = $PolicyId   -join ',' }

    if ($PSCmdlet.ParameterSetName -like '*Attributes') {
        $body = $Attributes
    }
    else {
        if ($PSBoundParameters.ContainsKey('ServerName') -and $PSBoundParameters.ContainsKey('ServerId')) {
            throw 'Specify either -ServerName or -ServerId, not both.'
        }
        if (-not $PSBoundParameters.ContainsKey('ServerName') -and -not $PSBoundParameters.ContainsKey('ServerId')) {
            throw 'A server identity is required: supply -ServerName or -ServerId (the object-store-account-exports POST body requires a server reference).'
        }

        $body = @{}
        # server is a scalar reference ({id, name, resource_type}); resource_type
        # is readOnly and must never be sent.
        if ($PSBoundParameters.ContainsKey('ServerName')) { $body['server'] = @{ name = $ServerName } }
        if ($PSBoundParameters.ContainsKey('ServerId'))   { $body['server'] = @{ id   = $ServerId } }
        if ($PSBoundParameters.ContainsKey('ExportEnabled')) { $body['export_enabled'] = $ExportEnabled }
    }

    $target = if ($PSBoundParameters.ContainsKey('MemberName')) { $MemberName -join ',' } else { $MemberId -join ',' }

    if ($PSCmdlet.ShouldProcess($target, 'Create object store account export')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-account-exports' -Body $body -QueryParams $queryParams
    }
}
