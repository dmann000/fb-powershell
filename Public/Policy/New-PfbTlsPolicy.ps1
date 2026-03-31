function New-PfbTlsPolicy {
    <#
    .SYNOPSIS
        Creates a new TLS policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbTlsPolicy cmdlet creates a new TLS policy on the connected Pure Storage
        FlashBlade. TLS policies define the minimum TLS version and allowed cipher suites.
    .PARAMETER Name
        The name for the new TLS policy.
    .PARAMETER Attributes
        A hashtable of TLS policy attributes such as min_version and ciphers.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbTlsPolicy -Name "tls-strict" -Attributes @{ min_version = "1.2" }

        Creates a TLS policy requiring TLS 1.2 minimum.
    .EXAMPLE
        New-PfbTlsPolicy -Name "tls-1.3-only" -Attributes @{ min_version = "1.3" }

        Creates a TLS policy requiring TLS 1.3.
    .EXAMPLE
        New-PfbTlsPolicy -Name "tls-test" -Attributes @{ min_version = "1.2" } -WhatIf

        Shows what would happen without actually creating the policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Create TLS policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'tls-policies' -Body $Attributes -QueryParams $q
    }
}
