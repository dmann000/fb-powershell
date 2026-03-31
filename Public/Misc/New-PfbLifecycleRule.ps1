function New-PfbLifecycleRule {
    <#
    .SYNOPSIS
        Creates a new object lifecycle rule on the FlashBlade.
    .DESCRIPTION
        Creates a lifecycle rule for an object store bucket to control automatic expiration
        and deletion of objects based on age or other criteria.
    .PARAMETER BucketName
        The name of the bucket to associate the lifecycle rule with.
    .PARAMETER Attributes
        A hashtable containing lifecycle rule attributes such as prefix, enabled status,
        and expiration settings.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbLifecycleRule -BucketName "mybucket" -Attributes @{ rule_id = "expire-30d"; keep_previous_version_for = 2592000000 }

        Creates a lifecycle rule on 'mybucket' that expires previous versions after 30 days.
    .EXAMPLE
        New-PfbLifecycleRule -BucketName "logs" -Attributes @{ rule_id = "cleanup"; prefix = "temp/"; keep_previous_version_for = 86400000 }

        Creates a lifecycle rule on 'logs' targeting objects with the 'temp/' prefix.
    .EXAMPLE
        $rule = @{ rule_id = "archive"; enabled = $true; keep_previous_version_for = 7776000000 }
        New-PfbLifecycleRule -BucketName "data" -Attributes $rule

        Creates an enabled lifecycle rule on the 'data' bucket with 90-day retention.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string]$BucketName,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $body = $Attributes
    if (-not $body.ContainsKey('bucket')) { $body['bucket'] = @{ name = $BucketName } }
    if ($PSCmdlet.ShouldProcess($BucketName, 'Create lifecycle rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'lifecycle-rules' -Body $body
    }
}
