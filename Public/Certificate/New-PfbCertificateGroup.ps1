function New-PfbCertificateGroup {
    <#
    .SYNOPSIS
        Creates a new certificate group on the FlashBlade.
    .DESCRIPTION
        The New-PfbCertificateGroup cmdlet creates a new certificate group on the connected
        FlashBlade. Certificate groups organize related CA certificates for use with directory
        services, KMIP, and other TLS-enabled integrations.
    .PARAMETER Name
        The name of the certificate group to create.
    .PARAMETER Attributes
        A hashtable defining the certificate group properties.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbCertificateGroup -Name 'ad-cert-group'

        Creates a new certificate group named 'ad-cert-group'.
    .EXAMPLE
        New-PfbCertificateGroup -Name 'ldap-certs' -Attributes @{ description = 'LDAP CA certificates' }

        Creates a new certificate group with a description.
    .EXAMPLE
        New-PfbCertificateGroup -Name 'kmip-certs' -Confirm:$false

        Creates a new certificate group without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create certificate group')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'certificate-groups' -Body $body -QueryParams $queryParams
    }
}
