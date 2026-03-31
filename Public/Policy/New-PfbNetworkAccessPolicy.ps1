function New-PfbNetworkAccessPolicy {
    <#
    .SYNOPSIS
        Creates a new network access policy on the FlashBlade.
    .DESCRIPTION
        Creates a new network access policy with the specified name and optional settings.
        Use the Attributes parameter to supply a complete body hashtable, or use
        individual parameters to build the request.
    .PARAMETER Name
        The name of the network access policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNetworkAccessPolicy -Name "net-access-01"

        Creates a new network access policy named 'net-access-01'.
    .EXAMPLE
        New-PfbNetworkAccessPolicy -Name "net-access-01" -Enabled

        Creates a new enabled network access policy.
    .EXAMPLE
        New-PfbNetworkAccessPolicy -Name "net-access-01" -Attributes @{ enabled = $true; rules = @(@{ client = "10.0.0.0/8"; effect = "allow" }) }

        Creates a new network access policy with custom attributes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create network access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-access-policies' -Body $body -QueryParams $queryParams
    }
}
