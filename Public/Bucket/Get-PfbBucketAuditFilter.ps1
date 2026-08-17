function Get-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Retrieves bucket audit filters from the FlashBlade.
    .DESCRIPTION
        Returns one or more bucket audit filters from the FlashBlade array.
        Audit filters control which S3 operations on a bucket are logged for
        auditing purposes. Filter results by audit filter name, by bucket name
        or ID, or use a server-side filter expression.
    .PARAMETER Name
        One or more audit filter names to retrieve.
    .PARAMETER BucketName
        One or more bucket names to retrieve audit filters for.
    .PARAMETER BucketId
        One or more bucket IDs to retrieve audit filters for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketAuditFilter

        Returns all bucket audit filters.
    .EXAMPLE
        Get-PfbBucketAuditFilter -BucketName "mybucket"

        Returns audit filters for the bucket named 'mybucket'.
    .EXAMPLE
        "bucket1", "bucket2" | Get-PfbBucketAuditFilter

        Returns audit filters for multiple buckets using pipeline input.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
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
        Assert-PfbSelectorNotCoerced -Value $BucketName -ParameterName 'BucketName' -Hint (
            'Pipe the bucket name instead, e.g. Get-PfbBucket | Select-Object -ExpandProperty name | ' +
            'Get-PfbBucketAuditFilter, or pass -BucketName explicitly.')
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($BucketName) { foreach ($b in $BucketName) { $allBucketNames.Add($b) } }
        if ($BucketId)   { foreach ($i in $BucketId)   { $allBucketIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allBucketNames.Count -gt 0) { $queryParams['bucket_names'] = $allBucketNames -join ',' }
        if ($allBucketIds.Count -gt 0)   { $queryParams['bucket_ids']   = $allBucketIds -join ',' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/audit-filters' -QueryParams $queryParams -AutoPaginate
    }
}
