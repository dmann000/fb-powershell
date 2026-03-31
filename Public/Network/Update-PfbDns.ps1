function Update-PfbDns {
    <#
    .SYNOPSIS
        Updates FlashBlade DNS configuration.
    .PARAMETER Domain
        The DNS domain name.
    .PARAMETER Nameservers
        An array of DNS nameserver IP addresses.
    .PARAMETER Attributes
        A hashtable of DNS attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbDns -Domain "example.com" -Nameservers "10.0.0.1", "10.0.0.2"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter()] [string]$Domain,
        [Parameter()] [string[]]$Nameservers,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($Domain)      { $body['domain'] = $Domain }
        if ($Nameservers) { $body['nameservers'] = $Nameservers }
    }

    if ($PSCmdlet.ShouldProcess('DNS', 'Update DNS configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'dns' -Body $body
    }
}
