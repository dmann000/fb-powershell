function Get-PfbDns {
    <#
    .SYNOPSIS
        Retrieves FlashBlade DNS configuration.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbDns
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)
    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'dns' -AutoPaginate
}
