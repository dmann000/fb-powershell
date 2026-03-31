function New-PfbDirectoryServiceRole {
    <#
    .SYNOPSIS
        Creates a new directory service role on the FlashBlade.
    .DESCRIPTION
        The New-PfbDirectoryServiceRole cmdlet creates a new directory service role on the
        connected Pure Storage FlashBlade. The role name is required and attributes define
        the role configuration including group and group base settings. Supports ShouldProcess
        for confirmation prompts.
    .PARAMETER Name
        The name of the directory service role to create.
    .PARAMETER Attributes
        A hashtable of role attributes to set (e.g., group, group_base).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbDirectoryServiceRole -Name "ad-admins" -Attributes @{ group = "CN=FB-Admins,OU=Groups,DC=corp,DC=example,DC=com"; group_base = "DC=corp,DC=example,DC=com" }

        Creates a new directory service role mapped to an Active Directory group.
    .EXAMPLE
        New-PfbDirectoryServiceRole -Name "readonly-users" -Attributes @{ group = "CN=FB-ReadOnly,OU=Groups,DC=corp,DC=example,DC=com" }

        Creates a new directory service role for read-only access.
    .EXAMPLE
        New-PfbDirectoryServiceRole -Name "test-role" -Attributes @{ } -WhatIf

        Shows what would happen if the role were created without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create directory service role')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'directory-services/roles' -Body $body -QueryParams $queryParams
    }
}
