function Update-PfbAlertWatcher {
    <#
    .SYNOPSIS
        Updates an alert watcher on the FlashBlade.
    .PARAMETER Name
        The name (email) of the alert watcher.
    .PARAMETER Id
        The ID of the alert watcher.
    .PARAMETER MinimumSeverity
        New minimum severity level.
    .PARAMETER Enabled
        Enable or disable the watcher.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbAlertWatcher -Name "admin@example.com" -MinimumSeverity "critical"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [ValidateSet('info', 'warning', 'critical')]
        [string]$MinimumSeverity,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($MinimumSeverity)    { $body['minimum_notification_severity'] = $MinimumSeverity }
            if ($PSBoundParameters.ContainsKey('Enabled'))  { $body['enabled'] = [bool]$Enabled }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update alert watcher')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'alert-watchers' -Body $body -QueryParams $queryParams
        }
    }
}
