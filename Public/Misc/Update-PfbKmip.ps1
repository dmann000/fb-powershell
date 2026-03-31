function Update-PfbKmip {
    <#
    .SYNOPSIS
        Updates KMIP server configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbKmip cmdlet modifies the Key Management Interoperability Protocol (KMIP)
        server configuration on the connected Pure Storage FlashBlade. Properties that can be
        updated include the KMIP server URI, certificate group, and connection settings.
    .PARAMETER Name
        The name of the KMIP server configuration to update.
    .PARAMETER Id
        The ID of the KMIP server configuration to update.
    .PARAMETER Attributes
        A hashtable of properties to update on the KMIP configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbKmip -Name 'kmip-server-1' -Attributes @{ uris = @('kmip.example.com:5696') }

        Updates the KMIP server URI.
    .EXAMPLE
        Update-PfbKmip -Name 'kmip-server-1' -Attributes @{ ca_certificate_group = @{ name = 'kmip-certs' } }

        Updates the CA certificate group used by the KMIP server.
    .EXAMPLE
        Update-PfbKmip -Name 'kmip-server-1' -Attributes @{ uris = @('kmip.example.com:5696') } -Confirm:$false

        Updates the KMIP configuration without prompting for confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

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

        if ($PSCmdlet.ShouldProcess($target, 'Update KMIP configuration')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'kmip' -Body $Attributes -QueryParams $queryParams
        }
    }
}
