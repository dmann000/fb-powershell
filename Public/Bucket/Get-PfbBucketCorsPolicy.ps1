function Get-PfbBucketCorsPolicy {
    <#
    .SYNOPSIS
        Retrieves bucket cross-origin resource sharing (CORS) policies from the FlashBlade.
    .DESCRIPTION
        Returns one or more bucket CORS policy associations from the FlashBlade array.
        CORS policies control which web origins are permitted to access S3 bucket
        resources from a browser. Filter results by fully-qualified name, bucket
        name, or bucket ID.

        NOTE: The FlashBlade API requires at least one of -Name, -BucketName, or
        -BucketId to be specified. GET
        /buckets/cross-origin-resource-sharing-policies declares no
        policy-level selector; 'policy_names' exists only on the /rules
        variant, so use Get-PfbBucketCorsPolicyRule -PolicyName for that. It
        also declares no 'ids' selector, so there is no -Id parameter: the
        endpoint silently ignored the key and returned the unfiltered
        collection.
    .PARAMETER Name
        One or more fully-qualified bucket CORS policy names.
    .PARAMETER BucketName
        One or more bucket names to retrieve CORS policies for.
    .PARAMETER BucketId
        One or more bucket IDs to retrieve CORS policies for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketCorsPolicy -BucketName "mybucket"

        Returns CORS policies associated with the bucket named 'mybucket'.
    .EXAMPLE
        Get-PfbBucketCorsPolicy -Name "mybucket/mycorspolicy"

        Returns a specific CORS policy by fully-qualified name.
    .EXAMPLE
        Get-PfbBucketCorsPolicy -BucketId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Returns CORS policies for the bucket with the given ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByBucketName')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter(ParameterSetName = 'ByBucketId')]
        [string[]]$BucketId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allBucketNames = [System.Collections.Generic.List[string]]::new()
        $allBucketIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($BucketName) { foreach ($b in $BucketName) { $allBucketNames.Add($b) } }
        if ($BucketId)   { foreach ($i in $BucketId)   { $allBucketIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allBucketNames.Count -gt 0) { $queryParams['bucket_names'] = $allBucketNames -join ',' }
        if ($allBucketIds.Count -gt 0)   { $queryParams['bucket_ids']   = $allBucketIds -join ',' }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/cross-origin-resource-sharing-policies' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Either names or ids' -or $_ -match 'Policy must be specified') {
                Write-Warning "Bucket CORS policies require the -Name parameter with a fully-qualified 'bucket/policy' name, or -BucketName/-BucketId."
                return
            }
            throw
        }
    }
}
