function New-PfbRealm {
    <#
    .SYNOPSIS
        Creates a new realm on the FlashBlade.
    .DESCRIPTION
        Creates a new realm with the specified name and optional attributes such as
        default_inbound_tls_policy.
    .PARAMETER Name
        The name of the realm to create.
    .PARAMETER Attributes
        A hashtable of additional attributes (e.g., @{ default_inbound_tls_policy = 'encrypt' }).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbRealm -Name "realm1"
    .EXAMPLE
        New-PfbRealm -Name "realm1" -Attributes @{ default_inbound_tls_policy = 'encrypt' }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) {
        $body = $Attributes
    }
    else {
        $body = @{}
    }

    $queryParams = @{
        'names' = $Name
        'without_default_access_list' = 'true'
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Create realm')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'realms' -Body $body -QueryParams $queryParams
    }
}
