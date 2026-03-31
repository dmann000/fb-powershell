function Update-PfbRealm {
    <#
    .SYNOPSIS
        Updates an existing realm on the FlashBlade.
    .DESCRIPTION
        Modifies realm attributes such as destroyed state or default_inbound_tls_policy.
        Use -Destroyed $false to recover a previously destroyed realm.
    .PARAMETER Name
        The name of the realm to update.
    .PARAMETER Id
        The ID of the realm to update.
    .PARAMETER Destroyed
        Set to $true to destroy or $false to recover the realm.
    .PARAMETER Attributes
        A hashtable of attributes to update (e.g., @{ default_inbound_tls_policy = 'encrypt' }).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbRealm -Name "realm1" -Destroyed $false
    .EXAMPLE
        Update-PfbRealm -Name "realm1" -Attributes @{ default_inbound_tls_policy = 'encrypt' }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Destroyed,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Destroyed')) { $body['destroyed'] = [bool]$Destroyed }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update realm')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'realms' -Body $body -QueryParams $queryParams
        }
    }
}
