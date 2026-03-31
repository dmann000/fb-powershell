function Get-PfbLifecycleRule {
    <#
    .SYNOPSIS
        Retrieves FlashBlade object lifecycle rules.
    .DESCRIPTION
        Returns lifecycle rules that control automatic expiration and deletion of objects
        in object store buckets. Rules can be filtered by name, ID, or bucket.
    .PARAMETER Name
        One or more lifecycle rule names to retrieve.
    .PARAMETER Id
        One or more lifecycle rule IDs to retrieve.
    .PARAMETER BucketName
        Filter lifecycle rules by the associated bucket name.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbLifecycleRule

        Retrieves all lifecycle rules on the FlashBlade.
    .EXAMPLE
        Get-PfbLifecycleRule -BucketName "mybucket"

        Retrieves lifecycle rules associated with the bucket named 'mybucket'.
    .EXAMPLE
        Get-PfbLifecycleRule -Name "expire-logs-30d"

        Retrieves the lifecycle rule named 'expire-logs-30d'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$BucketName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0) { $queryParams['ids'] = $allIds -join ',' }
        if ($BucketName) { $queryParams['bucket_names'] = $BucketName }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'lifecycle-rules' -QueryParams $queryParams -AutoPaginate
    }
}
