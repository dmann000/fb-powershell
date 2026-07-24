function Get-PfbAdminSetting {
    <#
    .SYNOPSIS
        Retrieves admin settings from the FlashBlade.
    .DESCRIPTION
        The Get-PfbAdminSetting cmdlet returns global administrator settings from the connected
        Pure Storage FlashBlade. These settings include lockout policy, single sign-on
        configuration, and other administrative-level options.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbAdminSetting

        Returns the current admin settings from the connected FlashBlade.
    .EXAMPLE
        $settings = Get-PfbAdminSetting; $settings.lockout_duration

        Retrieves admin settings and displays the lockout duration value.
    .EXAMPLE
        Get-PfbAdminSetting -Array $myFlashBlade

        Returns admin settings from a specific FlashBlade connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'admins/settings' -QueryParams $queryParams
    }
}
