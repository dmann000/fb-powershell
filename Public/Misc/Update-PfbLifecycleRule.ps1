function Update-PfbLifecycleRule {
    <#
    .SYNOPSIS
        Updates an object lifecycle rule on the FlashBlade.
    .DESCRIPTION
        Modifies the configuration of an existing lifecycle rule on the FlashBlade,
        such as changing the prefix filter, expiration period, or enabled status.
    .PARAMETER Name
        The name of the lifecycle rule to update.
    .PARAMETER Id
        The ID of the lifecycle rule to update.
    .PARAMETER Attributes
        A hashtable of lifecycle rule attributes to update, such as prefix,
        keep_previous_version_for, or enabled.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbLifecycleRule -Name "expire-logs-30d" -Attributes @{ keep_previous_version_for = 5184000000 }

        Updates the retention period of the lifecycle rule to 60 days.
    .EXAMPLE
        Update-PfbLifecycleRule -Name "cleanup" -Attributes @{ enabled = $false }

        Disables the lifecycle rule named 'cleanup'.
    .EXAMPLE
        Update-PfbLifecycleRule -Name "archive" -Attributes @{ prefix = "old/"; keep_previous_version_for = 7776000000 }

        Updates the prefix filter and retention period of the 'archive' rule.
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
        if ($PSCmdlet.ShouldProcess($target, 'Update lifecycle rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'lifecycle-rules' -Body $Attributes -QueryParams $queryParams
        }
    }
}
