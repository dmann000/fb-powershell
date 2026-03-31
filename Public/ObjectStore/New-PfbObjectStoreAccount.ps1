function New-PfbObjectStoreAccount {
    <#
    .SYNOPSIS
        Creates a new object store account on the FlashBlade.
    .PARAMETER Name
        The name of the account to create.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccount -Name "myaccount"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create object store account')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-accounts' -QueryParams $queryParams
    }
}
