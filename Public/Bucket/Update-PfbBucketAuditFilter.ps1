function Update-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Updates an existing bucket audit filter on the FlashBlade.
    .DESCRIPTION
        Modifies an existing audit filter for a bucket identified by member name
        or member ID. Use the individual typed parameters for a specific audit
        filter field, or the Attributes parameter to supply several properties
        to update at once as a hashtable.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value. -FilterNames is a query parameter and is orthogonal
        to the body, so it can be combined freely with either.
    .PARAMETER MemberName
        The name of the bucket whose audit filter should be updated. Sent as the
        'bucket_names' query parameter.
    .PARAMETER MemberId
        The ID of the bucket whose audit filter should be updated. Sent as the
        'bucket_ids' query parameter.
    .PARAMETER FilterNames
        The audit filter's own name(s), sent as the required 'names' query parameter.
        When not explicitly supplied, this defaults to -MemberName (audit filters are
        named after their owning bucket), so existing -MemberName-only callers keep
        working. If you only have -MemberId and the filter's name differs from the
        bucket's name, supply -FilterNames explicitly.
    .PARAMETER Actions
        The list of ops to be audited by this filter (e.g. 's3:GetObject'). No fixed
        value set is documented in the spec, so this is not validated against a closed
        list.
    .PARAMETER S3Prefixes
        The list of object name prefixes; ops in -Actions are audited only for objects
        matching these prefixes.
    .PARAMETER Attributes
        A hashtable of audit filter properties to update. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbBucketAuditFilter -MemberName "mybucket" -Actions "s3:GetObject","s3:PutObject"

        Updates the audit filter for 'mybucket' to log GetObject and PutObject operations
        using typed parameters.
    .EXAMPLE
        Update-PfbBucketAuditFilter -MemberId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -FilterNames "mybucket" -Actions "s3:DeleteObject"

        Updates the audit filter by bucket ID, explicitly supplying the filter's own name.
    .EXAMPLE
        Update-PfbBucketAuditFilter -MemberName "mybucket" -Attributes @{ actions = @("s3:GetObject","s3:PutObject") }

        Updates the audit filter for 'mybucket' using a raw attribute hashtable.
    .NOTES
        Wire-correctness fix: the real `PATCH /buckets/audit-filters` endpoint's query
        parameters are `bucket_ids`/`bucket_names` (confirmed directly against the real
        OpenAPI spec) -- not `member_ids`/`member_names`, which this cmdlet previously sent
        and which do not exist on this endpoint at all. -MemberName/-MemberId now map to the
        correct wire keys. Separately, the endpoint also requires a `names` query parameter
        on every PATCH (identifying the audit-filter resource itself) -- new -FilterNames
        parameter, defaulted from -MemberName for backward compatibility. `actions` and
        `s3_prefixes` are the only two real body properties on `BucketAuditFilterPost`;
        `bucket_ids`/`bucket_names`/`names` are query parameters only, never body fields.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByMemberNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByMemberNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByMemberNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByMemberIdAttributes',  Mandatory)]
        [string]$MemberId,

        # Constraint 17: `names` is a QUERY parameter, orthogonal to the request body, so
        # -FilterNames is declared bare rather than scoped to the *Individual sets.
        [Parameter()]
        [string[]]$FilterNames,

        [Parameter(ParameterSetName = 'ByMemberNameIndividual')]
        [Parameter(ParameterSetName = 'ByMemberIdIndividual')]
        [string[]]$Actions,

        [Parameter(ParameterSetName = 'ByMemberNameIndividual')]
        [Parameter(ParameterSetName = 'ByMemberIdIndividual')]
        [string[]]$S3Prefixes,

        [Parameter(ParameterSetName = 'ByMemberNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByMemberIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($MemberName) { $queryParams['bucket_names'] = $MemberName }
        if ($MemberId)   { $queryParams['bucket_ids']   = $MemberId }

        if ($PSBoundParameters.ContainsKey('FilterNames')) {
            $queryParams['names'] = @($FilterNames)
        }
        elseif ($MemberName) {
            # The real endpoint requires 'names' on every PATCH. Default to -MemberName
            # (audit filters are named after their owning bucket) so existing
            # -MemberName-only callers keep working without a breaking change.
            $queryParams['names'] = $MemberName
        }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Actions'))    { $body['actions']     = @($Actions) }
            if ($PSBoundParameters.ContainsKey('S3Prefixes')) { $body['s3_prefixes'] = @($S3Prefixes) }
        }

        $target = if ($MemberName) { $MemberName } else { $MemberId }

        if ($PSCmdlet.ShouldProcess($target, 'Update bucket audit filter')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'buckets/audit-filters' -Body $body -QueryParams $queryParams
        }
    }
}
