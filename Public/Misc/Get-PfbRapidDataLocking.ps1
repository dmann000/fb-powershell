function Get-PfbRapidDataLocking {
    <#
    .SYNOPSIS
        Retrieves rapid data locking status from the FlashBlade.
    .DESCRIPTION
        The Get-PfbRapidDataLocking cmdlet returns the rapid data locking configuration and
        status from the connected Pure Storage FlashBlade. Rapid data locking provides a fast
        mechanism to cryptographically erase all data on the array by destroying encryption keys.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbRapidDataLocking

        Returns the current rapid data locking status from the connected FlashBlade.
    .EXAMPLE
        $rdl = Get-PfbRapidDataLocking; $rdl.status

        Retrieves rapid data locking status and displays the current state.
    .EXAMPLE
        Get-PfbRapidDataLocking -Array $myFlashBlade

        Returns rapid data locking status from a specific FlashBlade connection.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'rapid-data-locking'
    }
}
