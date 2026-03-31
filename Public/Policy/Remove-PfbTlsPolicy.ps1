function Remove-PfbTlsPolicy {
    <#
    .SYNOPSIS
        Removes a TLS policy from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbTlsPolicy cmdlet deletes a TLS policy from the connected Pure Storage
        FlashBlade. The policy can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default.
    .PARAMETER Name
        The name of the TLS policy to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the TLS policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbTlsPolicy -Name "tls-old"

        Removes the TLS policy named "tls-old" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbTlsPolicy -Name "tls-test" -Confirm:$false

        Removes the TLS policy without prompting.
    .EXAMPLE
        Get-PfbTlsPolicy -Filter "name='temp-*'" | Remove-PfbTlsPolicy

        Removes matching TLS policies via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove TLS policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'tls-policies' -QueryParams $queryParams
        }
    }
}
