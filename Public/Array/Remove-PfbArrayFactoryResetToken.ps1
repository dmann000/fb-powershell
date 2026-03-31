function Remove-PfbArrayFactoryResetToken {
    <#
    .SYNOPSIS
        Removes the factory reset token from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbArrayFactoryResetToken cmdlet deletes the factory reset token from the
        connected Pure Storage FlashBlade, preventing a factory reset from being performed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbArrayFactoryResetToken

        Removes the factory reset token after prompting for confirmation.
    .EXAMPLE
        Remove-PfbArrayFactoryResetToken -Confirm:$false

        Removes the factory reset token without prompting.
    .EXAMPLE
        Remove-PfbArrayFactoryResetToken -WhatIf

        Shows what would happen without actually removing the token.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Remove factory reset token')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'arrays/factory-reset-token'
    }
}
