function Remove-PfbAlertWatcher {
    <#
    .SYNOPSIS
        Removes an alert watcher from the FlashBlade.
    .PARAMETER Name
        The name (email) of the alert watcher to remove.
    .PARAMETER Id
        The ID of the alert watcher to remove.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbAlertWatcher -Name "admin@example.com"
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove alert watcher')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'alert-watchers' -QueryParams $queryParams
        }
    }
}
