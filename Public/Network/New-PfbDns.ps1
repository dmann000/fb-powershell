function New-PfbDns {
    <#
    .SYNOPSIS
        Creates a new DNS configuration entry on a FlashBlade array.
    .DESCRIPTION
        The New-PfbDns cmdlet creates a new DNS configuration on the connected Pure Storage
        FlashBlade. DNS entries define name resolution servers and search domains.
    .PARAMETER Name
        The name for the new DNS configuration entry.
    .PARAMETER Attributes
        A hashtable of DNS attributes such as domain, nameservers, and search.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbDns -Name "dns-prod" -Attributes @{ domain = "example.com"; nameservers = @("10.0.0.1") }

        Creates a DNS entry with the specified domain and nameserver.
    .EXAMPLE
        New-PfbDns -Name "dns-secondary" -Attributes @{ nameservers = @("10.0.0.2","10.0.0.3") }

        Creates a DNS entry with multiple nameservers.
    .EXAMPLE
        New-PfbDns -Name "dns-test" -Attributes @{} -WhatIf

        Shows what would happen without actually creating the DNS entry.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create DNS configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'dns' -Body $Attributes -QueryParams $q
    }
}
