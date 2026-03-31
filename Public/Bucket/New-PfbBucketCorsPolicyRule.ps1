function New-PfbBucketCorsPolicyRule {
    <#
    .SYNOPSIS
        Creates a new bucket CORS policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to a cross-origin resource sharing (CORS) policy.
        Rules define allowed origins, HTTP methods, headers, exposed headers,
        and max age for cross-origin requests to S3 buckets.
    .PARAMETER Attributes
        A hashtable defining the rule properties (allowed_origins, allowed_methods,
        allowed_headers, exposed_headers, max_age_in_seconds, policy name references, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -Attributes @{ policy = @{ name = "allow-all-origins" }; allowed_origins = @("*"); allowed_methods = @("GET","PUT") }

        Creates a CORS rule allowing all origins with GET and PUT methods.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -Attributes @{ policy = @{ name = "restricted-cors" }; allowed_origins = @("https://example.com"); allowed_methods = @("GET"); max_age_in_seconds = 3600 }

        Creates a CORS rule for a specific origin with a max age of one hour.
    .EXAMPLE
        New-PfbBucketCorsPolicyRule -Attributes @{ policy = @{ name = "allow-all-origins" }; allowed_origins = @("*"); allowed_methods = @("GET","PUT","DELETE"); allowed_headers = @("*"); exposed_headers = @("ETag") }

        Creates a CORS rule with custom headers and exposed headers.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $target = 'CORS policy rule'
    if ($Attributes.policy -and $Attributes.policy.name) { $target = $Attributes.policy.name }

    if ($PSCmdlet.ShouldProcess($target, 'Create bucket CORS policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets/cross-origin-resource-sharing-policies/rules' -Body $Attributes
    }
}
