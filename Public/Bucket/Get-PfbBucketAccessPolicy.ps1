function Get-PfbBucketAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves bucket access policies from the FlashBlade.
    .DESCRIPTION
        Returns one or more bucket access policies from the FlashBlade array.
        Bucket access policies define S3 bucket-level access controls. Filter
        results by fully-qualified name (bucket/account:policy), or by bucket
        name or bucket ID.

        GET /buckets/bucket-access-policies declares no policy-level selector;
        'policy_names' exists only on the /rules variant, so use
        Get-PfbBucketAccessPolicyRule -PolicyName for
        that. It also declares no 'ids' selector, so there is no -Id parameter:
        the endpoint silently ignored the key and returned the unfiltered
        collection.
    .PARAMETER Name
        One or more fully-qualified bucket access policy names
        (e.g. 'mybucket/myaccount:mypolicy').
    .PARAMETER BucketName
        One or more bucket names to retrieve access policies for.
    .PARAMETER BucketId
        One or more bucket IDs to retrieve access policies for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketAccessPolicy -BucketName "mybucket"

        Returns access policies for the bucket named 'mybucket'.
    .EXAMPLE
        Get-PfbBucketAccessPolicy -Name "mybucket/myaccount:mypolicy"

        Returns the specific bucket access policy by fully-qualified name.
    .EXAMPLE
        Get-PfbBucketAccessPolicy -BucketId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Returns access policies for the bucket with the given ID.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByBucketName')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        # Within this family, the cross-endpoint chain from Get-PfbBucket into Get-PfbBucketAccessPolicy cannot
        # filter correctly: a producer's bare `name` bound to -BucketName / `bucket_names` is the defect
        # because `name` means different things by endpoint and metadata cannot identify its producer,
        # so no correct generic binding exists. An undeclared or non-matching query key returns HTTP 200
        # with the unfiltered collection; the guard's loud failure is therefore best. Do NOT remove it
        # or add an alias: that flips WrongScalar to Bound while sending the wrong name; revisit only if
        # the consumer can establish its producer, which parameter metadata alone cannot. Issue #90.
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
        Assert-PfbSelectorNotCoerced -Value $BucketName -OriginalInput $PSItem -ParameterName 'BucketName' -Hint (
            'Pipe the bucket name instead, e.g. Get-PfbBucket | Select-Object -ExpandProperty name | ' +
            'Get-PfbBucketAccessPolicy, or pass -BucketName explicitly.')
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($BucketName) { foreach ($b in $BucketName) { $allBucketNames.Add($b) } }
        if ($BucketId)   { foreach ($i in $BucketId)   { $allBucketIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allBucketNames.Count -gt 0) { $queryParams['bucket_names'] = $allBucketNames -join ',' }
        if ($allBucketIds.Count -gt 0)   { $queryParams['bucket_ids']   = $allBucketIds -join ',' }

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/bucket-access-policies' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Either names or ids' -or $_ -match 'Policy must be specified') {
                Write-Warning "Bucket access policies require the -Name parameter with a fully-qualified 'bucket/policy' name, or -BucketName/-BucketId. Use Get-PfbObjectStoreAccessPolicy to list available policies."
                return
            }
            throw
        }
    }
}
