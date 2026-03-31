function Update-PfbAdmin {
    <#
    .SYNOPSIS
        Updates a FlashBlade administrator account.
    .DESCRIPTION
        The Update-PfbAdmin cmdlet modifies attributes of an existing administrator account
        on the connected Pure Storage FlashBlade. The target administrator can be identified
        by name or ID. Common updates include role changes and password resets. Supports
        pipeline input and ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the administrator account to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the administrator account to update.
    .PARAMETER Attributes
        A hashtable of administrator attributes to modify (e.g., role, password).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAdmin -Name "pureuser" -Attributes @{ role = @{ name = "array_admin" } }

        Assigns the array_admin role to the administrator account named "pureuser".
    .EXAMPLE
        Update-PfbAdmin -Name "ops-admin" -Attributes @{ password = "N3wP@ssw0rd!" }

        Updates the password for the administrator account named "ops-admin".
    .EXAMPLE
        Update-PfbAdmin -Id "10314f42-020d-7080-8013-000ddt400012" -Attributes @{ role = @{ name = "readonly" } }

        Changes the role of the administrator identified by ID to readonly.
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
        if ($PSCmdlet.ShouldProcess($target, 'Update admin')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'admins' -Body $Attributes -QueryParams $queryParams
        }
    }
}
