function Update-PfbDirectoryServiceRole {
    <#
    .SYNOPSIS
        Updates an existing directory service role on the FlashBlade.
    .DESCRIPTION
        The Update-PfbDirectoryServiceRole cmdlet modifies attributes of an existing directory
        service role on the connected Everpure FlashBlade. The target role can be identified
        by name or ID. Supports ShouldProcess for confirmation prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the directory service role to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the directory service role to update.
    .PARAMETER Group
        Common Name (CN) of the directory service group containing users with authority level of
        the specified role name.
    .PARAMETER GroupBase
        Specifies where the configured group is located in the directory tree.
    .PARAMETER Attributes
        A hashtable of role attributes to modify (e.g., group, group_base). Mutually exclusive
        with the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbDirectoryServiceRole -Name "ad-admins" -Group "CN=FB-SuperAdmins,OU=Groups,DC=corp,DC=example,DC=com"

        Updates the group mapping for the directory service role "ad-admins" using a typed parameter.
    .EXAMPLE
        Update-PfbDirectoryServiceRole -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ group_base = "DC=corp,DC=example,DC=com" }

        Updates the group base for the directory service role identified by ID.
    .EXAMPLE
        Update-PfbDirectoryServiceRole -Name "test-role" -Attributes @{ } -WhatIf

        Shows what would happen if the role were updated without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$Group,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [string]$GroupBase,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

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

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Group'))     { $body['group']      = $Group }
            if ($PSBoundParameters.ContainsKey('GroupBase')) { $body['group_base'] = $GroupBase }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Update directory service role')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'directory-services/roles' -Body $body -QueryParams $queryParams
        }
    }
}
