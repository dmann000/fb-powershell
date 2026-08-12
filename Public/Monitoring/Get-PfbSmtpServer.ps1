function Get-PfbSmtpServer {
    <#
    .SYNOPSIS
        Retrieves the SMTP server configuration from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSmtpServer cmdlet returns the SMTP server configuration from the connected
        Everpure FlashBlade. It reads the /smtp-servers endpoint, which has carried the mail
        relay settings since REST 2.0 and is the only SMTP surface the module exposes.

        Note that `name` is the SMTP *resource* name (for example `management`), not the array
        name. The retired Get-PfbSmtp cmdlet read the legacy REST 1.12 /smtp path and returned
        the array name in that field.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSmtpServer

        Returns the SMTP server configuration for the connected FlashBlade.
    .EXAMPLE
        Get-PfbSmtpServer -Array $FlashBlade

        Returns the SMTP server configuration using a specific connection.
    .EXAMPLE
        (Get-PfbSmtpServer).relay_host

        Retrieves the configured SMTP relay host.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [int]$Limit,

        [Parameter()]
        [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $queryParams = @{}
    Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'smtp-servers' -QueryParams $queryParams
}
