function Get-PfbObjectStoreAccessPolicyAction {
    <#
    .SYNOPSIS
        Retrieves the list of supported object store access policy actions.
    .DESCRIPTION
        Returns the reference list of S3-compatible actions that can be used
        in object store access policy rules. This is read-only reference data
        provided by the FlashBlade API.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyAction
        Returns all supported access policy actions.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyAction -Filter "name='s3:Get*'"
        Returns actions matching the filter pattern.
    .EXAMPLE
        Get-PfbObjectStoreAccessPolicyAction -Sort "name" -Limit 20
        Returns a sorted, limited list of available actions.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Filter)     { $queryParams['filter']     = $Filter }
    if ($Sort)       { $queryParams['sort']       = $Sort }
    if ($Limit -gt 0) { $queryParams['limit']    = $Limit }
    if ($TotalOnly)  { $queryParams['total_only'] = 'true' }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-access-policy-actions' -QueryParams $queryParams -AutoPaginate
}
