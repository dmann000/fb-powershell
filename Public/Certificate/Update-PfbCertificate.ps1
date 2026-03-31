function Update-PfbCertificate {
    <#
    .SYNOPSIS
        Updates an existing SSL/TLS certificate on a Pure Storage FlashBlade.
    .DESCRIPTION
        The Update-PfbCertificate cmdlet modifies an existing certificate on the FlashBlade.
        The certificate can be identified by name or by ID. The Attributes hashtable contains
        the updated certificate data such as a renewed certificate body or a new private key.
        This cmdlet supports pipeline input by property name and the ShouldProcess pattern.
    .PARAMETER Name
        The name of the certificate to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the certificate to update.
    .PARAMETER Attributes
        A hashtable containing the updated certificate data. Supported keys include 'certificate',
        'key', and 'intermediate_certificate'.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbCertificate -Name 'web-cert' -Attributes @{ certificate = $newCertPem; key = $newKeyPem }

        Updates the certificate named 'web-cert' with a renewed certificate and key.
    .EXAMPLE
        Update-PfbCertificate -Id '10314f42-020d-7080-8013-000ddt400090' -Attributes @{ certificate = $certPem }

        Updates a certificate identified by its ID with a new certificate body.
    .EXAMPLE
        Get-PfbCertificate -Name 'web-cert' | Update-PfbCertificate -Attributes @{ intermediate_certificate = $chainPem }

        Pipes a certificate object to update its intermediate certificate chain.
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
        if ($PSCmdlet.ShouldProcess($target, 'Update certificate')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'certificates' -Body $Attributes -QueryParams $queryParams
        }
    }
}
