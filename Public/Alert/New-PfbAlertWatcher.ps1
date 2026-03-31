function New-PfbAlertWatcher {
    <#
    .SYNOPSIS
        Creates a new alert watcher on the FlashBlade.
    .PARAMETER Name
        The email address of the watcher.
    .PARAMETER MinimumSeverity
        Minimum severity level for notifications ('warning', 'info', 'error', 'critical').
    .PARAMETER Attributes
        A hashtable of additional attributes.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbAlertWatcher -Name "admin@example.com" -MinimumSeverity "warning"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('info', 'warning', 'error', 'critical')]
        [string]$MinimumSeverity,

        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($MinimumSeverity) { $body['minimum_notification_severity'] = $MinimumSeverity }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create alert watcher')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'alert-watchers' -Body $body -QueryParams $queryParams
    }
}
