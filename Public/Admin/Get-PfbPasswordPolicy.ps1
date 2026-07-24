function Get-PfbPasswordPolicy {
    <#
    .SYNOPSIS
        Retrieves the FlashBlade password policy configuration.
    .DESCRIPTION
        The Get-PfbPasswordPolicy cmdlet returns the password policy settings from the connected
        Pure Storage FlashBlade. This is a singleton resource that returns the current password
        complexity and expiration requirements configured on the array.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbPasswordPolicy

        Retrieves the password policy from the connected FlashBlade.
    .EXAMPLE
        $policy = Get-PfbPasswordPolicy; $policy.min_length

        Retrieves the password policy and inspects the minimum password length.
    .EXAMPLE
        Get-PfbPasswordPolicy -Array $secondArray

        Retrieves the password policy from a specific FlashBlade connection.
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
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'password-policies' -QueryParams $queryParams -AutoPaginate
}
