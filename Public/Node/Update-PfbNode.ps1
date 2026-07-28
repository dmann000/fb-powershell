function Update-PfbNode {
    <#
    .SYNOPSIS
        Updates a node on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbNode cmdlet modifies attributes of a node on the connected Everpure
        FlashBlade. The node can be identified by name or ID. Supports ShouldProcess for
        -WhatIf and -Confirm.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the node to update.
    .PARAMETER Id
        The ID of the node to update.
    .PARAMETER ManagementAddress
        The control IP address of the node. A connection is made to this address to get
        information on the node, such as the data addresses.
    .PARAMETER NewName
        A new user-specified name for the node.
    .PARAMETER NodeKey
        A key used to bootstrap a mTLS connection with the node being connected to. Cannot be
        specified together with -ManagementAddress or -SerialNumber.
    .PARAMETER SerialNumber
        The serial number of the node. If the given serial number does not match the serial
        number of the node, the request fails.
    .PARAMETER Attributes
        A hashtable of node attributes to modify. Mutually exclusive with the individual typed
        parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNode -Name "CH1.FB1" -Attributes @{ identify_enabled = $true }

        Enables the identification LED on the specified node.
    .EXAMPLE
        Update-PfbNode -Id "10314f42-020d-7080-8013-000ddt400005" -Attributes @{ identify_enabled = $false }

        Disables the identification LED on the node identified by ID.
    .EXAMPLE
        Update-PfbNode -Name "CH1.FB1" -Attributes @{ identify_enabled = $true } -WhatIf

        Shows what would happen without applying the change.
    .EXAMPLE
        Update-PfbNode -Name "CH1.FB1" -ManagementAddress "10.0.0.5"

        Updates the node's management address using a typed parameter.
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
        [string]$ManagementAddress,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NewName,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$NodeKey,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$SerialNumber,

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
            # EVERY value-carrying parameter is guarded by $PSBoundParameters.ContainsKey,
            # never by truthiness -- see Update-PfbAdmin.ps1 for the full rationale.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('ManagementAddress')) { $body['management_address'] = $ManagementAddress }

            # Exception: the body field is literally `name` (renames the resource), so the
            # parameter is -NewName, never -NodeName -- see Update-PfbWorkload / Update-PfbDataEvictionPolicy.
            if ($PSBoundParameters.ContainsKey('NewName'))           { $body['name'] = $NewName }

            if ($PSBoundParameters.ContainsKey('NodeKey'))           { $body['node_key'] = $NodeKey }
            if ($PSBoundParameters.ContainsKey('SerialNumber'))      { $body['serial_number'] = $SerialNumber }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update node')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'nodes' -Body $body -QueryParams $queryParams
        }
    }
}
