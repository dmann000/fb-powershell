function New-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Creates a new bucket audit filter on the FlashBlade.
    .DESCRIPTION
        Creates a new audit filter for a bucket on the FlashBlade array.
        Audit filters define which S3 operations are captured in audit logs
        for the specified bucket. Use the Attributes parameter to supply
        the filter configuration as a hashtable.
    .PARAMETER MemberName
        The name of the bucket to create the audit filter for.
    .PARAMETER Attributes
        A hashtable of audit filter properties for the request body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAuditFilter -MemberName "mybucket" -Attributes @{ actions = @("s3.GetObject") }

        Creates an audit filter for 'mybucket' that logs GetObject operations.
    .EXAMPLE
        New-PfbBucketAuditFilter -MemberName "mybucket" -Attributes @{ actions = @("s3.PutObject","s3.DeleteObject") }

        Creates an audit filter that logs PutObject and DeleteObject operations.
    .EXAMPLE
        New-PfbBucketAuditFilter -MemberName "mybucket" -Attributes @{}

        Creates an audit filter with default settings for the specified bucket.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$MemberName,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }

    $queryParams = @{ 'member_names' = $MemberName }

    if ($PSCmdlet.ShouldProcess($MemberName, 'Create bucket audit filter')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/audit-filters' -Body $body -QueryParams $queryParams
    }
}
