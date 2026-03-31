function Update-PfbDirectoryService {
    <#
    .SYNOPSIS
        Updates FlashBlade directory service configuration.
    .DESCRIPTION
        The Update-PfbDirectoryService cmdlet modifies the configuration of a directory service
        on the connected Pure Storage FlashBlade. Use this to configure LDAP URIs, base DNs,
        bind credentials, and other directory service settings for NFS, SMB, or management
        authentication. Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The directory service name to update (e.g., 'nfs', 'smb', 'management').
    .PARAMETER Attributes
        A hashtable of directory service attributes to modify, such as URIs, base DN,
        bind user, and bind password.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbDirectoryService -Name "nfs" -Attributes @{ uris = @("ldap://ldap.example.com") }

        Configures the NFS directory service to use the specified LDAP server.
    .EXAMPLE
        Update-PfbDirectoryService -Name "smb" -Attributes @{ uris = @("ldap://dc01.corp.com"); base_dn = "DC=corp,DC=com" }

        Updates the SMB directory service with a new LDAP URI and base DN.
    .EXAMPLE
        Update-PfbDirectoryService -Name "management" -Attributes @{ enabled = $true } -WhatIf

        Shows what would happen if the management directory service were enabled.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $Name }
    if ($PSCmdlet.ShouldProcess($Name, 'Update directory service')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'directory-services' -Body $Attributes -QueryParams $q
    }
}
