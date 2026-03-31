function Get-PfbArrayStorageClass {
    <#
    .SYNOPSIS
        Retrieves array storage class space information from a FlashBlade.
    .DESCRIPTION
        The Get-PfbArrayStorageClass cmdlet returns space usage broken down by storage class
        from the connected Pure Storage FlashBlade.

        Note: Storage classes are only supported on certain FlashBlade models (e.g.,
        FlashBlade//S and FlashBlade//E). On unsupported models, this cmdlet returns
        nothing and writes a warning.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayStorageClass

        Retrieves space usage for all storage classes.
    .EXAMPLE
        Get-PfbArrayStorageClass -Sort "name" -Limit 10

        Retrieves up to 10 storage class entries sorted by name.
    .EXAMPLE
        Get-PfbArrayStorageClass -Filter "name='default'"

        Retrieves space usage for the default storage class.
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
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    try {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/space/storage-classes' -QueryParams $queryParams -AutoPaginate
    }
    catch {
        if ($_ -match 'not supported' -or $_ -match '400') {
            Write-Warning "Storage classes are not supported on this FlashBlade model. This feature requires FlashBlade//S or FlashBlade//E."
            return
        }
        throw
    }
}
