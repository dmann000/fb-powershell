function Get-PfbAuditFileSystemPolicyOperation {
    <#
    .SYNOPSIS
        Retrieves available audit file-system policy operations.
    .DESCRIPTION
        The Get-PfbAuditFileSystemPolicyOperation cmdlet returns the reference data for
        audit file-system policy operations from the connected Pure Storage FlashBlade.
        This is read-only reference data that describes which operations can be audited.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAuditFileSystemPolicyOperation

        Retrieves all available audit file-system policy operations.
    .EXAMPLE
        Get-PfbAuditFileSystemPolicyOperation -Limit 5

        Retrieves up to 5 audit file-system policy operations.
    .EXAMPLE
        Get-PfbAuditFileSystemPolicyOperation -Filter "name='read'" -Sort "name"

        Retrieves operations matching the filter, sorted by name.
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

    try {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'audit-file-systems-policy-operations' -QueryParams $queryParams -AutoPaginate
    }
    catch {
        if ($_ -match 'not supported' -or $_ -match 'Operation not permitted') {
            Write-Warning "Audit file-system policy operations are not supported on this FlashBlade model or configuration."
            return
        }
        throw
    }
}
