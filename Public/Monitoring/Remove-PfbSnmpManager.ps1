function Remove-PfbSnmpManager {
    <#
    .SYNOPSIS
        Removes an SNMP manager (trap host) from a Pure Storage FlashBlade.
    .DESCRIPTION
        The Remove-PfbSnmpManager cmdlet deletes an SNMP manager entry from the FlashBlade.
        The manager can be identified by name or by ID. This operation has a high confirm impact
        and will prompt for confirmation by default. The cmdlet accepts pipeline input for
        manager names.
    .PARAMETER Name
        The name of the SNMP manager to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the SNMP manager to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSnmpManager -Name 'snmp-mgr01'

        Removes the SNMP manager named 'snmp-mgr01' after prompting for confirmation.
    .EXAMPLE
        Remove-PfbSnmpManager -Name 'snmp-mgr-old' -Confirm:$false

        Removes the SNMP manager without prompting for confirmation.
    .EXAMPLE
        Get-PfbSnmpManager | Where-Object { $_.name -like '*-decom' } | Remove-PfbSnmpManager

        Pipes decommissioned SNMP managers to be removed from the FlashBlade.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove SNMP manager')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'snmp-managers' -QueryParams $queryParams
        }
    }
}
