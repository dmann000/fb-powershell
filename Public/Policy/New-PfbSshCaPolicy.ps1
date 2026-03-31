function New-PfbSshCaPolicy {
    <#
    .SYNOPSIS
        Creates a new SSH certificate authority policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbSshCaPolicy cmdlet creates a new SSH certificate authority policy on the
        connected Pure Storage FlashBlade. SSH CA policies define certificate-based authentication
        rules for SSH access.
    .PARAMETER Name
        The name for the new SSH CA policy.
    .PARAMETER Attributes
        A hashtable of SSH CA policy attributes to configure, such as public_key and enabled.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSshCaPolicy -Name "ssh-ca-prod" -Attributes @{ public_key = "ssh-rsa AAAA..." }

        Creates a new SSH CA policy with the specified public key.
    .EXAMPLE
        New-PfbSshCaPolicy -Name "ssh-ca-test" -Attributes @{ enabled = $true } -WhatIf

        Shows what would happen without actually creating the policy.
    .EXAMPLE
        New-PfbSshCaPolicy -Name "ssh-ca-dev" -Attributes @{ public_key = "ssh-ed25519 AAAA..." }

        Creates a new SSH CA policy with an Ed25519 public key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create SSH CA policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'ssh-certificate-authority-policies' -Body $Attributes -QueryParams $q
    }
}
