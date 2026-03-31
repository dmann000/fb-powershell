function Update-PfbLegalHold {
    <#
    .SYNOPSIS
        Updates an existing legal hold on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLegalHold cmdlet modifies a legal hold on the connected Pure Storage
        FlashBlade. Identify the hold by name or ID and supply the changed properties via
        the Attributes parameter.
    .PARAMETER Name
        The name of the legal hold to update.
    .PARAMETER Id
        The ID of the legal hold to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the legal hold.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLegalHold -Name "litigation-hold-2024" -Attributes @{ description = 'Updated description' }

        Updates the description on the specified legal hold.
    .EXAMPLE
        Update-PfbLegalHold -Id "12345" -Attributes @{ enabled = $false }

        Disables the legal hold identified by ID.
    .EXAMPLE
        Update-PfbLegalHold -Name "litigation-hold-2024" -Attributes @{ enabled = $true }

        Enables the specified legal hold.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

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
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update legal hold')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'legal-holds' -Body $body -QueryParams $queryParams
        }
    }
}
