function New-PfbObjectStoreUser {
    <#
    .SYNOPSIS
        Creates a new object store user on the FlashBlade.
    .PARAMETER Name
        The name of the user to create (format: account/username).
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreUser -Name "myaccount/myuser"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store user')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-users' -QueryParams $queryParams
    }
}
