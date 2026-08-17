function New-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Creates a new bucket audit filter on the FlashBlade.
    .DESCRIPTION
        Creates a new audit filter for a bucket on the FlashBlade array.
        Audit filters define which S3 operations are captured in audit logs
        for the specified bucket. Use the Attributes parameter to supply
        the filter configuration as a hashtable.

        NOTE: POST /buckets/audit-filters requires the 'names' query parameter
        on every request, and the request body carries no bucket identity, so
        the bucket must be supplied separately as 'bucket_names'. -BucketName
        is therefore mandatory and -Name is combinable with it; when -Name is
        omitted, 'names' defaults to the bucket name (audit filters are named
        after their owning bucket).
    .PARAMETER BucketName
        One or more bucket names to create the audit filter for. Sent as the
        'bucket_names' query parameter.
    .PARAMETER Name
        One or more audit filter names to create, sent as the required 'names'
        query parameter. Defaults to -BucketName when not supplied.
    .PARAMETER Attributes
        A hashtable of audit filter properties for the request body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAuditFilter -BucketName "mybucket" -Attributes @{ actions = @("s3.GetObject") }

        Creates an audit filter named 'mybucket' on the bucket 'mybucket' that
        logs GetObject operations.
    .EXAMPLE
        New-PfbBucketAuditFilter -BucketName "mybucket" -Name "myfilter" -Attributes @{ actions = @("s3.PutObject","s3.DeleteObject") }

        Creates an audit filter named 'myfilter' on the bucket 'mybucket' that
        logs PutObject and DeleteObject operations.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$BucketName,

        [Parameter(Position = 1)]
        [string[]]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }

    # 'names' is required on every POST. Default it from the bucket name when
    # the caller did not name the filter explicitly.
    $filterNames = if ($Name) { $Name } else { $BucketName }

    $queryParams = @{}
    $queryParams['names']        = $filterNames -join ','
    $queryParams['bucket_names'] = $BucketName -join ','

    $target = "$($filterNames -join ',') on bucket(s) $($BucketName -join ',')"

    if ($PSCmdlet.ShouldProcess($target, 'Create bucket audit filter')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/audit-filters' -Body $body -QueryParams $queryParams
    }
}
