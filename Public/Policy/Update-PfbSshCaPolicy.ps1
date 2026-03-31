function Update-PfbSshCaPolicy {
    <#
    .SYNOPSIS
        Updates an existing SSH certificate authority policy on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbSshCaPolicy cmdlet modifies attributes of an existing SSH CA policy on
        the connected Pure Storage FlashBlade. The policy can be identified by name or ID.
    .PARAMETER Name
        The name of the SSH CA policy to update.
    .PARAMETER Id
        The ID of the SSH CA policy to update.
    .PARAMETER Attributes
        A hashtable of SSH CA policy attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbSshCaPolicy -Name "ssh-ca-prod" -Attributes @{ enabled = $true }

        Enables the SSH CA policy named "ssh-ca-prod".
    .EXAMPLE
        Update-PfbSshCaPolicy -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ public_key = "ssh-rsa NEW..." }

        Updates the public key of the SSH CA policy by ID.
    .EXAMPLE
        Update-PfbSshCaPolicy -Name "ssh-ca-prod" -Attributes @{ enabled = $false } -WhatIf

        Shows what would happen without actually updating the policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update SSH CA policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'ssh-certificate-authority-policies' -Body $Attributes -QueryParams $queryParams
        }
    }
}
