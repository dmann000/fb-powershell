function Get-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Retrieves bucket audit filters from the FlashBlade.
    .DESCRIPTION
        Returns one or more bucket audit filters from the FlashBlade array.
        Audit filters control which S3 operations on a bucket are logged for
        auditing purposes. Filter results by bucket member name or ID, or use
        a server-side filter expression.
    .PARAMETER MemberName
        One or more bucket names to retrieve audit filters for.
    .PARAMETER MemberId
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
        Get-PfbBucketAuditFilter -MemberName "mybucket"

        Returns audit filters for the bucket named 'mybucket'.
    .EXAMPLE
        "bucket1", "bucket2" | Get-PfbBucketAuditFilter

        Returns audit filters for multiple buckets using pipeline input.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByMemberName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberId')]
        [string[]]$MemberId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allMemberNames = [System.Collections.Generic.List[string]]::new()
        $allMemberIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($MemberName) { foreach ($n in $MemberName) { $allMemberNames.Add($n) } }
        if ($MemberId)   { foreach ($i in $MemberId)   { $allMemberIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($allMemberIds.Count -gt 0)   { $queryParams['member_ids']   = $allMemberIds -join ',' }
        if ($Filter)                      { $queryParams['filter']       = $Filter }
        if ($Sort)                        { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)               { $queryParams['limit']        = $Limit }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/audit-filters' -QueryParams $queryParams -AutoPaginate
    }
}
