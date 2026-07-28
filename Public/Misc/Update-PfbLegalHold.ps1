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
    .PARAMETER Description
        The description of the legal hold instance.
    .PARAMETER Attributes
        A hashtable of attributes to update on the legal hold. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLegalHold -Name "litigation-hold-2024" -Description 'Updated description'

        Updates the description on the specified legal hold using a typed parameter.
    .EXAMPLE
        Update-PfbLegalHold -Id "12345" -Attributes @{ enabled = $false }

        Disables the legal hold identified by ID.
    .EXAMPLE
        Update-PfbLegalHold -Name "litigation-hold-2024" -Attributes @{ enabled = $true }

        Enables the specified legal hold.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Description,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every value-carrying parameter is guarded by ContainsKey, never truthiness -- see
            # the canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Description')) { $body['description'] = $Description }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update legal hold')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'legal-holds' -Body $body -QueryParams $queryParams
        }
    }
}
