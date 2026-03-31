function Remove-PfbSyslogServer {
    <#
    .SYNOPSIS
        Removes a syslog server configuration from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbSyslogServer cmdlet deletes a syslog server configuration from the
        connected Pure Storage FlashBlade. The target server can be identified by name or ID.
        This cmdlet has a high confirm impact and will prompt for confirmation by default.
        Supports pipeline input for batch removal operations.
    .PARAMETER Name
        The name of the syslog server to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the syslog server to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSyslogServer -Name "syslog-old"

        Removes the syslog server named "syslog-old" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbSyslogServer -Name "syslog-test" -Confirm:$false

        Removes the syslog server named "syslog-test" without prompting for confirmation.
    .EXAMPLE
        Get-PfbSyslogServer -Filter "enabled='false'" | Remove-PfbSyslogServer

        Removes all disabled syslog server configurations via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove syslog server')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'syslog-servers' -QueryParams $queryParams
        }
    }
}
