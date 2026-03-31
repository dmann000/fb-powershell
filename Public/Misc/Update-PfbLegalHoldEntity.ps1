function Update-PfbLegalHoldEntity {
    <#
    .SYNOPSIS
        Updates a held entity under a legal hold on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLegalHoldEntity cmdlet modifies the properties of an entity that is
        subject to a legal hold on the connected Pure Storage FlashBlade. Identify the
        held entity by name and supply the changed properties via Attributes.
    .PARAMETER Name
        The name of the held entity to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the held entity.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name "fs1" -Attributes @{ description = 'Updated hold reason' }

        Updates the description on the held entity named "fs1".
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name "bucket1" -Attributes @{ enabled = $false }

        Disables the held entity named "bucket1".
    .EXAMPLE
        Update-PfbLegalHoldEntity -Name "fs1" -Attributes @{ hold_type = 'litigation' }

        Updates the hold type on the specified held entity.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $body = if ($Attributes) { $Attributes } else { @{} }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }

        if ($PSCmdlet.ShouldProcess($Name, 'Update legal hold entity')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'legal-holds/held-entities' -Body $body -QueryParams $queryParams
        }
    }
}
