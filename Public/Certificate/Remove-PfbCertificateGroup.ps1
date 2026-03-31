function Remove-PfbCertificateGroup {
    <#
    .SYNOPSIS
        Removes a certificate group from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbCertificateGroup cmdlet deletes a certificate group from the connected
        FlashBlade. This operation is high-impact because removing a certificate group may
        affect directory services and other TLS-enabled features that reference the group.
    .PARAMETER Name
        The name of the certificate group to remove.
    .PARAMETER Id
        The ID of the certificate group to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbCertificateGroup -Name 'ad-cert-group'

        Removes the certificate group named 'ad-cert-group' after confirmation.
    .EXAMPLE
        Remove-PfbCertificateGroup -Name 'ad-cert-group' -Confirm:$false

        Removes the certificate group without prompting for confirmation.
    .EXAMPLE
        Get-PfbCertificateGroup -Name 'old-group' | Remove-PfbCertificateGroup

        Removes a certificate group via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove certificate group')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'certificate-groups' -QueryParams $queryParams
        }
    }
}
