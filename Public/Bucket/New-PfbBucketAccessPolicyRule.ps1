function New-PfbBucketAccessPolicyRule {
    <#
    .SYNOPSIS
        Creates a new bucket access policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to a bucket access policy. Rules define specific
        permissions such as allowed actions, principals, resources, and
        conditions within the policy for the specified bucket.
    .PARAMETER MemberName
        The name of the bucket the access policy belongs to.
    .PARAMETER PolicyName
        The name of the access policy to add the rule to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (actions, principals,
        resources, effect, conditions, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -MemberName "mybucket" -PolicyName "read-only-policy" -Attributes @{ effect = "allow"; actions = @("s3:GetObject"); principals = @("*") }

        Creates a rule allowing all principals to perform GetObject.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -MemberName "mybucket" -PolicyName "write-policy" -Attributes @{ effect = "allow"; actions = @("s3:PutObject","s3:DeleteObject"); principals = @("user1") }

        Creates a rule allowing user1 to write and delete objects.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -MemberName "mybucket" -PolicyName "full-access" -Attributes @{ effect = "allow"; actions = @("s3:*"); principals = @("*") }

        Creates a rule granting full S3 access to all principals.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$MemberName,

        [Parameter(Mandatory, Position = 1)]
        [string]$PolicyName,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'member_names' = $MemberName
        'policy_names' = $PolicyName
    }

    if ($PSCmdlet.ShouldProcess("$MemberName / $PolicyName", 'Create bucket access policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/bucket-access-policies/rules' -Body $Attributes -QueryParams $queryParams
    }
}
