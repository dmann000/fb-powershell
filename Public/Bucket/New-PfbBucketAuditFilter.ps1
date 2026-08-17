function New-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Creates a new bucket audit filter on the FlashBlade.
    .DESCRIPTION
        Creates a new audit filter for a bucket on the FlashBlade array.
        Audit filters define which S3 operations are captured in audit logs
        for the specified bucket. Use the Attributes parameter to supply
        the filter configuration as a hashtable.
    .PARAMETER Name
        One or more audit filter names to create.
    .PARAMETER BucketName
        One or more bucket names to create the audit filter for.
    .PARAMETER Attributes
        A hashtable of audit filter properties for the request body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAuditFilter -BucketName "mybucket" -Attributes @{ actions = @("s3.GetObject") }

        Creates an audit filter for 'mybucket' that logs GetObject operations.
    .EXAMPLE
        New-PfbBucketAuditFilter -BucketName "mybucket" -Attributes @{ actions = @("s3.PutObject","s3.DeleteObject") }

        Creates an audit filter that logs PutObject and DeleteObject operations.
    .EXAMPLE
        New-PfbBucketAuditFilter -Name "myfilter" -Attributes @{}

        Creates an audit filter with default settings using the given filter name.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByBucketName')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, Position = 0)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketName', Mandatory, Position = 0)]
        [string[]]$BucketName,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }

    $queryParams = @{}
    if ($Name)       { $queryParams['names']        = $Name -join ',' }
    if ($BucketName) { $queryParams['bucket_names'] = $BucketName -join ',' }

    $target = if ($Name) { $Name -join ',' } else { $BucketName -join ',' }

    if ($PSCmdlet.ShouldProcess($target, 'Create bucket audit filter')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/audit-filters' -Body $body -QueryParams $queryParams
    }
}
