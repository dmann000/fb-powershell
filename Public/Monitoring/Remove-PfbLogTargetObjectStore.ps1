function Remove-PfbLogTargetObjectStore {
    <#
    .SYNOPSIS
        Removes a log-target object-store configuration from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbLogTargetObjectStore cmdlet deletes a log-target object-store
        configuration from the connected Pure Storage FlashBlade. The target is identified
        by name or ID. This is a destructive operation and requires confirmation.
    .PARAMETER Name
        The name of the log-target object store to remove.
    .PARAMETER Id
        The ID of the log-target object store to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbLogTargetObjectStore -Name "log-obj-target1"

        Removes the log-target object-store configuration named "log-obj-target1".
    .EXAMPLE
        Remove-PfbLogTargetObjectStore -Id "12345" -Confirm:$false

        Removes the log-target object store by ID without prompting for confirmation.
    .EXAMPLE
        Get-PfbLogTargetObjectStore -Name "log-obj-target1" | Remove-PfbLogTargetObjectStore

        Retrieves and removes the specified log-target object store via pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Remove log-target object store')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'log-targets/object-store' -QueryParams $queryParams
        }
    }
}
