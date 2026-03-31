function Remove-PfbLifecycleRule {
    <#
    .SYNOPSIS
        Removes an object lifecycle rule from the FlashBlade.
    .DESCRIPTION
        Deletes a lifecycle rule from the FlashBlade array. Once removed, the automatic
        expiration and deletion policy defined by the rule will no longer be applied.
    .PARAMETER Name
        The name of the lifecycle rule to remove.
    .PARAMETER Id
        The ID of the lifecycle rule to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbLifecycleRule -Name "expire-logs-30d"

        Removes the lifecycle rule named 'expire-logs-30d' after confirmation.
    .EXAMPLE
        Remove-PfbLifecycleRule -Name "cleanup" -Confirm:$false

        Removes the lifecycle rule named 'cleanup' without prompting for confirmation.
    .EXAMPLE
        Remove-PfbLifecycleRule -Id "10314f42-020d-7080-8013-000ddt400090"

        Removes the lifecycle rule with the specified ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)] [string]$Name,
        [Parameter(ParameterSetName = 'ById', Mandatory)] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Remove lifecycle rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'lifecycle-rules' -QueryParams $queryParams
        }
    }
}
