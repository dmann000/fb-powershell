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
        A hashtable defining the rule properties. Sent as the request body.

        The BucketAccessPolicyRulePost schema declares exactly four properties, and
        constrains three of them in their descriptions rather than in an enum:

          actions    - array of string; the only supported action is "s3:GetObject".
          principals - an OBJECT, not a string array, shaped @{ all = $true };
                       only all-principals is supported.
          resources  - array of string; only all objects in a bucket is supported,
                       e.g. @("mybucket/*").
          effect     - readOnly, so a caller cannot send it. It is always "allow".

        Anything outside that set -- a narrower action, a named principal, a
        principals string array, or a caller-supplied effect -- the endpoint does not
        accept. Verified against every spec version the endpoint exists in
        (REST 2.12 through 2.28); the shape is identical throughout.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -BucketName "mybucket" -PolicyName "mybucket/myaccount:read-only-policy" -Name "allow-get" -Attributes @{ actions = @("s3:GetObject"); principals = @{ all = $true } }

        Creates a rule named 'allow-get' allowing all principals to perform GetObject.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -BucketName "mybucket" -PolicyName "mybucket/myaccount:read-only-policy" -Name "allow-get" -Attributes @{ actions = @("s3:GetObject"); principals = @{ all = $true }; resources = @("mybucket/*") }

        Creates the same rule with the resource scope stated explicitly.
    .EXAMPLE
        New-PfbBucketAccessPolicyRule -BucketName "mybucket","archive" -PolicyName "mybucket/myaccount:read-only-policy","archive/myaccount:read-only-policy" -Name "allow-get" -Attributes @{ actions = @("s3:GetObject"); principals = @{ all = $true } }

        Creates the rule across two buckets in one call; each selector is joined into
        its comma-separated query key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        # ValidateNotNullOrEmpty on all three selectors: each feeds a query key the
        # endpoint requires or matches on, and an empty array or an array of empty
        # strings would otherwise join to '' and put a blank selector on the wire. The
        # Mandatory binder already rejects @() and @('') on both editions, so this is
        # belt-and-braces against a future edit that drops Mandatory.
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$BucketName,

        [Parameter(Mandatory, Position = 1, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$PolicyName,

        [Parameter(Mandatory, Position = 2)]
        [ValidateNotNullOrEmpty()]
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
