function Update-PfbNetworkAccessPolicy {
    <#
    .SYNOPSIS
        Updates an existing network access policy on the FlashBlade.
    .DESCRIPTION
        Modifies an existing network access policy identified by name or ID.
        Supports enabling or disabling the policy and updating attributes.
        The Enabled parameter accepts $true or $false and can be used with
        the colon syntax (e.g. -Enabled:$false).
    .PARAMETER Name
        The name of the network access policy to update.
    .PARAMETER Id
        The ID of the network access policy to update.
    .PARAMETER Enabled
        Enable or disable the network access policy. Use -Enabled:$true or -Enabled:$false.
    .PARAMETER Attributes
        A hashtable of attributes to update. When specified, this is used as the
        entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNetworkAccessPolicy -Name "net-access-01" -Enabled:$false

        Disables the network access policy named 'net-access-01'.
    .EXAMPLE
        Update-PfbNetworkAccessPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Enabled:$true

        Enables the network access policy by ID.
    .EXAMPLE
        Update-PfbNetworkAccessPolicy -Name "net-access-01" -Attributes @{ rules = @(@{ client = "192.168.0.0/16"; effect = "deny" }) }

        Updates the network access policy rules using an attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update network access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'network-access-policies' -Body $body -QueryParams $queryParams
        }
    }
}
