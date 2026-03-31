function Update-PfbTarget {
    <#
    .SYNOPSIS
        Updates an existing replication target on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbTarget cmdlet modifies attributes of an existing replication target on the
        connected Pure Storage FlashBlade. The target can be identified by name or ID. Common
        updates include changing the address, credentials, or connection settings. Supports
        pipeline input and ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the replication target to update. Accepts pipeline input by property name.
    .PARAMETER Id
        The ID of the replication target to update.
    .PARAMETER Attributes
        A hashtable of target attributes to modify.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbTarget -Name "s3-target-aws" -Attributes @{ address = "s3.us-east-1.amazonaws.com" }

        Updates the address for the replication target named "s3-target-aws".
    .EXAMPLE
        Update-PfbTarget -Name "remote-fb-dc2" -Attributes @{ connection_key = "new-key-456" }

        Updates the connection key for the "remote-fb-dc2" replication target.
    .EXAMPLE
        Update-PfbTarget -Id "10314f42-020d-7080-8013-000ddt400099" -Attributes @{ enabled = $true }

        Enables the replication target identified by the specified ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)] [string]$Name,
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
        if ($Id) { $queryParams['ids'] = $Id }
        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update target')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'targets' -Body $Attributes -QueryParams $queryParams
        }
    }
}
