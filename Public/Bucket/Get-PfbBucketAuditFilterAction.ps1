function Get-PfbBucketAuditFilterAction {
    <#
    .SYNOPSIS
        Retrieves available bucket audit filter actions from the FlashBlade.
    .DESCRIPTION
        Returns the list of valid S3 actions that can be used when configuring
        bucket audit filters. This is a read-only reference endpoint that
        describes available audit action types.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketAuditFilterAction

        Returns all available bucket audit filter actions.
    .EXAMPLE
        Get-PfbBucketAuditFilterAction -Limit 10

        Returns the first 10 available audit filter actions.
    .EXAMPLE
        Get-PfbBucketAuditFilterAction -Sort "name"

        Returns all audit filter actions sorted by name.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Filter)     { $queryParams['filter'] = $Filter }
    if ($Sort)       { $queryParams['sort']   = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'bucket-audit-filter-actions' -QueryParams $queryParams -AutoPaginate
}
