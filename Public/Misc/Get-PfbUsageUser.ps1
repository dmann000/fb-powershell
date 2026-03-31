function Get-PfbUsageUser {
    <#
    .SYNOPSIS
        Retrieves FlashBlade file system usage information per user.
    .DESCRIPTION
        Returns storage usage statistics broken down by user for a specified file system.
        Useful for monitoring per-user consumption and enforcing quota policies.
    .PARAMETER FileSystemName
        The name of the file system to retrieve user usage for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., 'usage-' for descending usage).
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbUsageUser

        Retrieves user usage information for all file systems.
    .EXAMPLE
        Get-PfbUsageUser -FileSystemName "fs1"

        Retrieves user usage information for the file system named 'fs1'.
    .EXAMPLE
        Get-PfbUsageUser -FileSystemName "fs1" -Sort "usage-" -Limit 10

        Retrieves the top 10 users by usage on file system 'fs1'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$FileSystemName,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    if ($FileSystemName) { $queryParams['file_system_names'] = $FileSystemName }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Sort) { $queryParams['sort'] = $Sort }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'usage/users' -QueryParams $queryParams -AutoPaginate
}
