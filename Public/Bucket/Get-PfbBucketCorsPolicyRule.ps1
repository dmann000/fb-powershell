function Get-PfbBucketCorsPolicyRule {
    <#
    .SYNOPSIS
        Retrieves bucket CORS policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for bucket cross-origin resource sharing (CORS) policies.
        Rules define allowed origins, HTTP methods, headers, and max age for
        cross-origin requests to the S3 bucket. Filter by fully-qualified name,
        bucket name, or policy name.

        NOTE: The FlashBlade API requires at least one of -Name, -BucketName, or
        -PolicyName to be specified. GET
        /buckets/cross-origin-resource-sharing-policies/rules declares no 'ids'
        selector, so there is no -Id parameter: the endpoint silently ignored the
        key and returned the unfiltered collection.
    .PARAMETER Name
        One or more fully-qualified bucket CORS policy rule names.
    .PARAMETER BucketName
        One or more bucket names to retrieve CORS policy rules for.
    .PARAMETER PolicyName
        One or more CORS policy names to retrieve rules for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketCorsPolicyRule -BucketName "mybucket"

        Returns all bucket CORS policy rules for the specified bucket.
    .EXAMPLE
        Get-PfbBucketCorsPolicyRule -PolicyName "allow-all-origins"

        Returns rules for the CORS policy named 'allow-all-origins'.
    .EXAMPLE
        Get-PfbBucketCorsPolicyRule -BucketName "mybucket" -PolicyName "allow-all-origins"

        Returns CORS rules for a specific policy on a specific bucket.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByBucketName')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allBucketNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($BucketName) { foreach ($b in $BucketName) { $allBucketNames.Add($b) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allBucketNames.Count -gt 0) { $queryParams['bucket_names'] = $allBucketNames -join ',' }
        if ($PolicyName)                 { $queryParams['policy_names'] = $PolicyName -join ',' }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/cross-origin-resource-sharing-policies/rules' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Either names or ids' -or $_ -match 'Policy must be specified') {
                Write-Warning "Bucket CORS policy rules require the -Name parameter with a fully-qualified name, or -BucketName/-PolicyName."
                return
            }
            throw
        }
    }
}
