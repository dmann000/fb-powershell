function Remove-PfbCertificate {
    <#
    .SYNOPSIS
        Removes an SSL/TLS certificate from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Remove-PfbCertificate cmdlet deletes a certificate from the FlashBlade. The certificate
        can be identified by name or by ID. This operation has a high confirm impact and will prompt
        for confirmation by default. The cmdlet accepts pipeline input for certificate names.
    .PARAMETER Name
        The name of the certificate to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the certificate to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbCertificate -Name 'expired-cert'

        Removes the certificate named 'expired-cert' after prompting for confirmation.
    .EXAMPLE
        Remove-PfbCertificate -Name 'old-cert' -Confirm:$false

        Removes the certificate without prompting for confirmation.
    .EXAMPLE
        Get-PfbCertificate -Filter "valid_to<'2025-01-01'" | Remove-PfbCertificate

        Pipes expired certificates to be removed from the FlashBlade.
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
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove certificate')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'certificates' -QueryParams $queryParams
        }
    }
}
