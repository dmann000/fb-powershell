function Update-PfbDirectoryServiceRole {
    <#
    .SYNOPSIS
        Updates an existing directory service role on the FlashBlade.
    .DESCRIPTION
        The Update-PfbDirectoryServiceRole cmdlet modifies attributes of an existing directory
        service role on the connected Pure Storage FlashBlade. The target role can be identified
        by name or ID. Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the directory service role to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the directory service role to update.
    .PARAMETER Attributes
        A hashtable of role attributes to modify (e.g., group, group_base).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbDirectoryServiceRole -Name "ad-admins" -Attributes @{ group = "CN=FB-SuperAdmins,OU=Groups,DC=corp,DC=example,DC=com" }

        Updates the group mapping for the directory service role "ad-admins".
    .EXAMPLE
        Update-PfbDirectoryServiceRole -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ group_base = "DC=corp,DC=example,DC=com" }

        Updates the group base for the directory service role identified by ID.
    .EXAMPLE
        Update-PfbDirectoryServiceRole -Name "test-role" -Attributes @{ } -WhatIf

        Shows what would happen if the role were updated without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update directory service role')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'directory-services/roles' -Body $Attributes -QueryParams $queryParams
        }
    }
}
