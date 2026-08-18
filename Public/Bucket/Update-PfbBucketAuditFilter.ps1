function Update-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Updates an existing bucket audit filter on the FlashBlade.
    .DESCRIPTION
        Modifies an existing audit filter for a bucket identified by bucket name
        or bucket ID. Use the individual typed parameters for a specific audit
        filter field, or the Attributes parameter to supply several properties
        to update at once as a hashtable.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value. -Name is a query parameter and is orthogonal
        to the body, so it can be combined freely with either.
    .PARAMETER BucketName
        The name of the bucket whose audit filter should be updated. Sent as the
        'bucket_names' query parameter.
    .PARAMETER BucketId
        The ID of the bucket whose audit filter should be updated. Sent as the
        'bucket_ids' query parameter.
    .PARAMETER Name
        The audit filter's own name(s), sent as the required 'names' query parameter.
        When not explicitly supplied, this defaults to -BucketName (audit filters are
        named after their owning bucket), so existing -BucketName-only callers keep
        working. If you only have -BucketId and the filter's name differs from the
        bucket's name, supply -Name explicitly.
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
        Update-PfbBucketAuditFilter -BucketName "mybucket" -Actions "s3:GetObject","s3:PutObject"

        Updates the audit filter for 'mybucket' to log GetObject and PutObject operations
        using typed parameters.
    .EXAMPLE
        Update-PfbBucketAuditFilter -BucketId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Name "mybucket" -Actions "s3:DeleteObject"

        Updates the audit filter by bucket ID, explicitly supplying the filter's own name.
    .EXAMPLE
        Update-PfbBucketAuditFilter -BucketName "mybucket" -Attributes @{ actions = @("s3:GetObject","s3:PutObject") }

        Updates the audit filter for 'mybucket' using a raw attribute hashtable.
    .NOTES
        Wire-correctness fix: the real `PATCH /buckets/audit-filters` endpoint's query
        parameters are `bucket_ids`/`bucket_names` (confirmed directly against the real
        OpenAPI spec) -- not `member_ids`/`member_names`, which this cmdlet previously sent
        and which do not exist on this endpoint at all. -BucketName/-BucketId map to the
        correct wire keys, and their names now match the keys they carry as well as the
        rest of the Pfb bucket-audit-filter family. Separately, the endpoint also requires
        a `names` query parameter on every PATCH (identifying the audit-filter resource
        itself) -- the -Name parameter, defaulted from -BucketName for convenience.
        `actions` and `s3_prefixes` are the only two real body properties on
        `BucketAuditFilterPost`; `bucket_ids`/`bucket_names`/`names` are query parameters
        only, never body fields.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByBucketNameIndividual')]
    param(
        # The three aliases below restore the pre-rename names so existing callers keep
        # working. Note the deliberate asymmetry with the Remove-Pfb* cmdlets in this family,
        # which underwent the same MemberName/MemberId -> BucketName/BucketId rename on this
        # branch and were given NO aliases: their legacy parameters wrote query keys the
        # endpoint does not declare, so they over-deleted rather than filtering. Aliasing
        # those onto a key that does work would quietly change what a DELETE removes, which
        # is worse than the break. Here the old names genuinely worked, so restoring them
        # restores working behaviour and nothing else. Do not "fix" the inconsistency by
        # adding aliases there.
        [Parameter(ParameterSetName = 'ByBucketNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByBucketNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('MemberName')]
        [string]$BucketName,

        [Parameter(ParameterSetName = 'ByBucketIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByBucketIdAttributes',  Mandatory)]
        [Alias('MemberId')]
        [string]$BucketId,

        # Constraint 17: `names` is a QUERY parameter, orthogonal to the request body, so
        # -Name is declared bare rather than scoped to the *Individual sets. Being bare it
        # is also reachable in every parameter set, which the endpoint's `required: true`
        # on `names` demands.
        #
        # ValidateNotNullOrEmpty is load-bearing here, not decoration: -Name is NOT
        # Mandatory, so without it `-Name @()` and `-Name @('')` both bind happily,
        # $PSBoundParameters.ContainsKey('Name') is true, and `names` goes on the wire
        # empty -- a required selector silently dropped. Verified on pwsh 7 and Windows
        # PowerShell 5.1 that this attribute rejects both forms.
        [Parameter()]
        [Alias('FilterNames')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketNameIndividual')]
        [Parameter(ParameterSetName = 'ByBucketIdIndividual')]
        [string[]]$Actions,

        [Parameter(ParameterSetName = 'ByBucketNameIndividual')]
        [Parameter(ParameterSetName = 'ByBucketIdIndividual')]
        [string[]]$S3Prefixes,

        [Parameter(ParameterSetName = 'ByBucketNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByBucketIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($BucketName) { $queryParams['bucket_names'] = $BucketName }
        if ($BucketId)   { $queryParams['bucket_ids']   = $BucketId }

        if ($PSBoundParameters.ContainsKey('Name')) {
            $queryParams['names'] = $Name -join ','
        }
        elseif ($BucketName) {
            # The real endpoint requires 'names' on every PATCH. Default to -BucketName
            # (audit filters are named after their owning bucket) so -BucketName-only
            # callers do not have to restate the same value twice.
            $queryParams['names'] = $BucketName
        }
        else {
            # -BucketId alone gives no value to infer -Name from (the audit filter's
            # own name cannot be derived from the bucket's ID). Fail fast client-side rather
            # than send a request the array will reject anyway for missing the required
            # 'names' query parameter.
            throw "Update-PfbBucketAuditFilter: -Name is required when -BucketId is used without -BucketName -- the audit filter's own name cannot be inferred from an ID alone. Supply -Name explicitly."
        }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Actions'))    { $body['actions']     = @($Actions) }
            if ($PSBoundParameters.ContainsKey('S3Prefixes')) { $body['s3_prefixes'] = @($S3Prefixes) }
        }

        $target = if ($BucketName) { $BucketName } else { $BucketId }

        if ($PSCmdlet.ShouldProcess($target, 'Update bucket audit filter')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'buckets/audit-filters' -Body $body -QueryParams $queryParams
        }
    }
}
