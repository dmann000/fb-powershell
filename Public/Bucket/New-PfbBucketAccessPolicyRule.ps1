function New-PfbBucketAccessPolicyRule {
    <#
    .SYNOPSIS
        Creates a new bucket access policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to a bucket access policy. Rules define specific
        permissions such as allowed actions, principals, resources, and
        conditions within the policy for the specified bucket.

        NOTE: POST /buckets/bucket-access-policies/rules declares 'names' as a
        REQUIRED query parameter alongside 'bucket_names', 'bucket_ids' and
        'policy_names'. Because 'names' is required on every call, -Name is
        Mandatory and this cmdlet deliberately publishes a single parameter set,
        so the required key can never be unreachable. The previous -MemberName
        parameter wrote 'member_names', which this endpoint does not declare, so
        the array silently discarded it -- and the required 'names' key was never
        sent at all.
    .PARAMETER BucketName
        One or more bucket names the access policy belongs to. Sent as
        'bucket_names'.
    .PARAMETER PolicyName
        One or more access policy names to add the rule to. Sent as
        'policy_names'.
    .PARAMETER Name
        One or more names for the new rule. Sent as 'names'. Required by the
        endpoint.
    .PARAMETER Attributes
        A hashtable defining the rule properties (actions, principals,
        resources, conditions, etc.). Sent as the request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -BucketName "mybucket" -PolicyName "read-only-policy" -Name "allow-get" -Attributes @{ actions = @("s3:GetObject"); principals = @("*") }

        Creates a rule named 'allow-get' allowing all principals to perform GetObject.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -BucketName "mybucket" -PolicyName "write-policy" -Name "allow-write" -Attributes @{ actions = @("s3:PutObject","s3:DeleteObject"); principals = @("user1") }

        Creates a rule allowing user1 to write and delete objects.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -BucketName "mybucket" -PolicyName "full-access" -Name "allow-all" -Attributes @{ actions = @("s3:*"); principals = @("*") }

        Creates a rule granting full S3 access to all principals.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [string[]]$PolicyName,

        [Parameter(Mandatory, Position = 2)]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{
            'names'        = $Name -join ','
            'bucket_names' = $BucketName -join ','
            'policy_names' = $PolicyName -join ','
        }

        if ($PSCmdlet.ShouldProcess("$($BucketName -join ',') / $($PolicyName -join ',') / $($Name -join ',')", 'Create bucket access policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/bucket-access-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
