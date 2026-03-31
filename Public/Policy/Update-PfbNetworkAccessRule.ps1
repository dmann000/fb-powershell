function Update-PfbNetworkAccessRule {
    <#
    .SYNOPSIS
        Updates an existing network access policy rule on the FlashBlade.
    .DESCRIPTION
        Modifies an existing rule in a network access policy identified by rule name.
        Use the Attributes parameter to supply the properties to update such as
        client, effect, interfaces, or protocols.
    .PARAMETER Name
        The name of the network access rule to update (e.g. 'network-access-01.1').
    .PARAMETER Attributes
        A hashtable of rule properties to update. Only specified properties are changed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbNetworkAccessRule -Name "network-access-01.1" -Attributes @{ client = "10.0.0.0/8" }

        Updates the client pattern of the specified rule.
    .EXAMPLE
        Update-PfbNetworkAccessRule -Name "network-access-01.1" -Attributes @{ effect = "deny" }

        Changes the effect of the specified rule to deny.
    .EXAMPLE
        Update-PfbNetworkAccessRule -Name "network-access-01.1" -Attributes @{ client = "192.168.0.0/16"; interfaces = @("data") }

        Updates the client and interfaces of the specified rule.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }

        if ($PSCmdlet.ShouldProcess($Name, 'Update network access rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'network-access-policies/rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
