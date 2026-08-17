function New-PfbBucketCorsPolicyRule {
    <#
    .SYNOPSIS
        Creates a new bucket CORS policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to a cross-origin resource sharing (CORS) policy. Rules
        define the allowed origins, HTTP methods and headers for cross-origin
        requests to an S3 bucket.

        NOTE: POST /buckets/cross-origin-resource-sharing-policies/rules declares
        'names' as a REQUIRED query parameter, alongside 'bucket_names',
        'bucket_ids' and 'policy_names' ('context_names' joins at REST 2.17).
        This cmdlet previously sent no query parameters at all, so it could never
        satisfy the required 'names' and the call could not succeed. Because
        'names' is required on every call, -Name is Mandatory and this cmdlet
        publishes a single parameter set, so the required key is reachable by
        construction and can never be made mutually exclusive with a bucket or
        policy selector.

        The request body declares only allowed_headers, allowed_methods and
        allowed_origins -- it carries no identity of its own, so nothing in the
        body overlaps the query keys. In particular there is no 'policy' body
        field: the owning policy is identified by 'policy_names' on the query
        string.
    .PARAMETER BucketName
        One or more bucket names the CORS policy belongs to. Sent as
        'bucket_names'.
    .PARAMETER PolicyName
        One or more CORS policy names to add the rule to. Sent as 'policy_names'.
    .PARAMETER Name
        One or more names for the new rule. Sent as 'names'. Required by the
        endpoint.
    .PARAMETER Attributes
        A hashtable defining the rule properties. The endpoint accepts
        allowed_origins, allowed_methods and allowed_headers. Sent as the request
        body.

        The schema constrains the VALUES as well as the field names, in its
        descriptions rather than in an enum: the only supported allowed_origins is
        "*", the only supported allowed_headers is "*", and the only supported
        allowed_methods is the complete set
        @("GET", "PUT", "HEAD", "POST", "DELETE"). Any narrower origin, header or
        method subset is rejected by the array, so the examples below deliberately
        show only the supported combination.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -BucketName "mybucket" -PolicyName "mybucket/cors-policy" -Name "allow-all" -Attributes @{ allowed_origins = @("*"); allowed_methods = @("GET","PUT","HEAD","POST","DELETE") }

        Creates a CORS rule allowing all origins with the complete supported method set.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -BucketName "web-assets" -PolicyName "web-assets/cors-policy" -Name "allow-all" -Attributes @{ allowed_origins = @("*"); allowed_methods = @("GET","PUT","HEAD","POST","DELETE"); allowed_headers = @("*") }

        Creates the same rule with allowed_headers stated explicitly.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -BucketName "mybucket","web-assets" -PolicyName "mybucket/cors-policy","web-assets/cors-policy" -Name "allow-all" -Attributes @{ allowed_origins = @("*"); allowed_methods = @("GET","PUT","HEAD","POST","DELETE") }

        Creates the rule across two buckets in one call; each selector is joined into
        its comma-separated query key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        # ValidateNotNullOrEmpty on all three selectors: each one feeds a query key the
        # endpoint requires or matches on, and an empty array or an array of empty
        # strings would otherwise join to '' and put a blank selector on the wire. The
        # Mandatory binder already rejects @() and @('') on both editions, so this is
        # belt-and-braces against a future edit that drops Mandatory -- it is NOT
        # belt-and-braces on -Name of Update-PfbBucketAuditFilter, which is not
        # Mandatory and where the hole was real.
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

        if ($PSCmdlet.ShouldProcess("$($BucketName -join ',') / $($PolicyName -join ',') / $($Name -join ',')", 'Create bucket CORS policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/cross-origin-resource-sharing-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
