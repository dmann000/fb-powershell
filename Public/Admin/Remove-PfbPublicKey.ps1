function Remove-PfbPublicKey {
    <#
    .SYNOPSIS
        Removes a public key from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbPublicKey cmdlet deletes a public key from the connected Pure Storage
        FlashBlade. This is a high-impact operation because removing a public key will
        immediately revoke SSH key-based authentication for any account using the key.
    .PARAMETER Name
        The name of the public key to remove.
    .PARAMETER Id
        The ID of the public key to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbPublicKey -Name 'admin-ssh-key'

        Removes the public key named 'admin-ssh-key' after confirmation.
    .EXAMPLE
        Remove-PfbPublicKey -Name 'admin-ssh-key' -Confirm:$false

        Removes the public key without prompting for confirmation.
    .EXAMPLE
        Get-PfbPublicKey -Name 'old-key' | Remove-PfbPublicKey

        Removes a public key via pipeline input.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove public key')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'public-keys' -QueryParams $queryParams
        }
    }
}
