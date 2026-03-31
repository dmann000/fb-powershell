function Update-PfbArrayEula {
    <#
    .SYNOPSIS
        Updates the EULA acceptance on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbArrayEula cmdlet modifies the End User License Agreement acceptance
        status on the connected Pure Storage FlashBlade.
    .PARAMETER Attributes
        A hashtable of EULA attributes to modify, typically including the signature.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbArrayEula -Attributes @{ signature = @{ accepted = $true; company = "Acme Corp" } }

        Accepts the EULA with the specified company name.
    .EXAMPLE
        Update-PfbArrayEula -Attributes @{ signature = @{ accepted = $true; name = "John Doe"; title = "Admin" } }

        Accepts the EULA with signatory details.
    .EXAMPLE
        Update-PfbArrayEula -Attributes @{} -WhatIf

        Shows what would happen without actually updating the EULA.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Update EULA acceptance')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'arrays/eula' -Body $Attributes
    }
}
