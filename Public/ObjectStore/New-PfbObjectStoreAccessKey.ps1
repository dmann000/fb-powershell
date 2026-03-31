function New-PfbObjectStoreAccessKey {
    <#
    .SYNOPSIS
        Creates a new object store access key on the FlashBlade.
    .PARAMETER UserName
        The object store user name (format: account/username).
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbObjectStoreAccessKey -UserName "myaccount/myuser"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$UserName,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = @{
        user = @{ name = $UserName }
    }

    if ($PSCmdlet.ShouldProcess($UserName, 'Create object store access key')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'object-store-access-keys' -Body $body
    }
}
