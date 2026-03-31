function Remove-PfbQosPolicy {
    <#
    .SYNOPSIS
        Removes a QoS policy from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbQosPolicy cmdlet deletes a QoS policy from the connected Pure Storage
        FlashBlade. The policy can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default.
    .PARAMETER Name
        The name of the QoS policy to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the QoS policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbQosPolicy -Name "qos-old"

        Removes the QoS policy after prompting for confirmation.
    .EXAMPLE
        Remove-PfbQosPolicy -Name "qos-test" -Confirm:$false

        Removes the QoS policy without prompting.
    .EXAMPLE
        Get-PfbQosPolicy -Filter "enabled='false'" | Remove-PfbQosPolicy

        Removes all disabled QoS policies via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove QoS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'qos-policies' -QueryParams $queryParams
        }
    }
}
