function Update-PfbSupportVerificationKey {
    <#
    .SYNOPSIS
        Updates support verification key settings on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSupportVerificationKey cmdlet modifies the support verification key
        configuration on the connected Pure Storage FlashBlade.
    .PARAMETER Attributes
        A hashtable of verification key attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSupportVerificationKey -Attributes @{ enabled = $true }

        Enables the support verification key.
    .EXAMPLE
        Update-PfbSupportVerificationKey -Attributes @{ key = "new-verification-key" }

        Updates the verification key value.
    .EXAMPLE
        Update-PfbSupportVerificationKey -Attributes @{ enabled = $false } -WhatIf

        Shows what would happen without actually updating the verification key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Update support verification key')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'support/verification-keys' -Body $Attributes
    }
}
