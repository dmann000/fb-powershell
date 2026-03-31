function Update-PfbManagementAccessPolicy {
    <#
    .SYNOPSIS
        Updates an existing management access policy on the FlashBlade.
    .DESCRIPTION
        The Update-PfbManagementAccessPolicy cmdlet modifies attributes of an existing management
        access policy on the connected Pure Storage FlashBlade. The target policy can be identified
        by name or ID. Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the management access policy to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the management access policy to update.
    .PARAMETER Attributes
        A hashtable of policy attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Name "ops-policy" -Attributes @{ allowed_operations = @("read","write") }

        Updates the operations allowed by the "ops-policy" management access policy.
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Id "abc12345-6789-0abc-def0-123456789abc" -Attributes @{ enabled = $true }

        Enables the management access policy identified by ID.
    .EXAMPLE
        Update-PfbManagementAccessPolicy -Name "test-policy" -Attributes @{ } -WhatIf

        Shows what would happen if the policy were updated without making changes.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update management access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'management-access-policies' -Body $Attributes -QueryParams $queryParams
        }
    }
}
