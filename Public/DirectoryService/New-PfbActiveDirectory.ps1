function New-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Joins the FlashBlade to an Active Directory domain.
    .DESCRIPTION
        The New-PfbActiveDirectory cmdlet joins the connected Pure Storage FlashBlade to an
        Active Directory domain. The Attributes hashtable must include the domain name,
        computer account name, and credentials for the domain join operation. Supports
        ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name for the Active Directory configuration entry.
    .PARAMETER Attributes
        A hashtable of Active Directory join attributes including domain, computer_name,
        user, and password. Additional optional settings such as directory_servers and
        encryption_types may also be specified.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbActiveDirectory -Name "ad1" -Attributes @{ domain = "corp.example.com"; computer_name = "FB01"; user = "admin"; password = "P@ssw0rd" }

        Joins the FlashBlade to the corp.example.com domain with the computer name FB01.
    .EXAMPLE
        $adParams = @{
            domain           = "corp.example.com"
            computer_name    = "FLASHBLADE01"
            user             = "svc-fbjoin"
            password         = "SecurePass123"
            directory_servers = @("dc01.corp.example.com")
        }
        New-PfbActiveDirectory -Name "ad-prod" -Attributes $adParams

        Joins the FlashBlade to Active Directory with explicit directory server targeting.
    .EXAMPLE
        New-PfbActiveDirectory -Name "ad-test" -Attributes @{ domain = "test.local"; computer_name = "FBTEST"; user = "admin"; password = "Test123" } -WhatIf

        Shows what would happen if the FlashBlade were joined to the test.local domain.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Join Active Directory')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'active-directory' -Body $Attributes -QueryParams $q
    }
}
