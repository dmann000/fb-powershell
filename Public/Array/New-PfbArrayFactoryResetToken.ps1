function New-PfbArrayFactoryResetToken {
    <#
    .SYNOPSIS
        Creates a factory reset token on a FlashBlade array.
    .DESCRIPTION
        The New-PfbArrayFactoryResetToken cmdlet generates a new factory reset token on the
        connected Pure Storage FlashBlade. WARNING: This token can be used to completely
        erase and reset the array. Use with extreme caution.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbArrayFactoryResetToken

        Creates a factory reset token after prompting for confirmation.
    .EXAMPLE
        New-PfbArrayFactoryResetToken -Confirm:$false

        Creates a factory reset token without prompting (use with extreme caution).
    .EXAMPLE
        New-PfbArrayFactoryResetToken -WhatIf

        Shows what would happen without actually creating the token.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter()] [PSCustomObject]$Array)
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Create factory reset token (DANGEROUS)')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'arrays/factory-reset-token'
    }
}
