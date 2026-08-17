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
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -BucketName "mybucket" -PolicyName "mybucket/cors-policy" -Name "allow-all" -Attributes @{ allowed_origins = @("*"); allowed_methods = @("GET","PUT") }

        Creates a CORS rule allowing all origins with GET and PUT methods.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -BucketName "web-assets" -PolicyName "web-assets/cors-policy" -Name "example-only" -Attributes @{ allowed_origins = @("https://example.com"); allowed_methods = @("GET") }

        Creates a CORS rule for a single origin.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -BucketName "mybucket" -PolicyName "mybucket/cors-policy" -Name "allow-all" -Attributes @{ allowed_origins = @("*"); allowed_methods = @("GET","PUT","DELETE"); allowed_headers = @("*") }

        Creates a CORS rule with custom allowed headers.
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

        if ($PSCmdlet.ShouldProcess("$($BucketName -join ',') / $($PolicyName -join ',') / $($Name -join ',')", 'Create bucket CORS policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/cross-origin-resource-sharing-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
