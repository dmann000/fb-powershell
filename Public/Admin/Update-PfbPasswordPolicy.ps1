function Update-PfbPasswordPolicy {
    <#
    .SYNOPSIS
        Updates the FlashBlade password policy configuration.
    .DESCRIPTION
        The Update-PfbPasswordPolicy cmdlet modifies the password policy settings on the connected
        Pure Storage FlashBlade. Use the Attributes hashtable to specify password complexity and
        expiration requirements. This is a singleton resource. Supports ShouldProcess for
        confirmation prompts.
    .PARAMETER Attributes
        A hashtable of password policy attributes to modify (e.g., min_length, require_uppercase,
        require_lowercase, require_numeric, require_special, max_age).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbPasswordPolicy -Attributes @{ min_length = 12 }

        Sets the minimum password length to 12 characters.
    .EXAMPLE
        Update-PfbPasswordPolicy -Attributes @{ min_length = 10; require_uppercase = $true; require_special = $true }

        Updates multiple password policy requirements at once.
    .EXAMPLE
        Update-PfbPasswordPolicy -Attributes @{ max_age = 7776000000 } -WhatIf

        Shows what would happen if the password max age were updated without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ShouldProcess('password-policies', 'Update password policy')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'password-policies' -Body $Attributes
    }
}
