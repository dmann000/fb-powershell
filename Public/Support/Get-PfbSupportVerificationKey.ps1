function Get-PfbSupportVerificationKey {
    <#
    .SYNOPSIS
        Retrieves support verification keys from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSupportVerificationKey cmdlet returns support verification key information
        from the connected Pure Storage FlashBlade. Verification keys are used for secure
        support access and validation.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSupportVerificationKey

        Retrieves all support verification keys from the connected FlashBlade.
    .EXAMPLE
        Get-PfbSupportVerificationKey -Limit 5

        Retrieves up to 5 support verification keys.
    .EXAMPLE
        Get-PfbSupportVerificationKey -Array $FlashBlade

        Retrieves verification keys using a specific FlashBlade connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'support/verification-keys' -QueryParams $queryParams -AutoPaginate
}
