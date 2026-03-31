function Remove-PfbSshCaPolicy {
    <#
    .SYNOPSIS
        Removes an SSH certificate authority policy from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbSshCaPolicy cmdlet deletes an SSH CA policy from the connected Pure Storage
        FlashBlade. The policy can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default.
    .PARAMETER Name
        The name of the SSH CA policy to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the SSH CA policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSshCaPolicy -Name "ssh-ca-old"

        Removes the SSH CA policy named "ssh-ca-old" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbSshCaPolicy -Name "ssh-ca-test" -Confirm:$false

        Removes the SSH CA policy without prompting.
    .EXAMPLE
        Get-PfbSshCaPolicy -Filter "enabled='false'" | Remove-PfbSshCaPolicy

        Removes all disabled SSH CA policies via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove SSH CA policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'ssh-certificate-authority-policies' -QueryParams $queryParams
        }
    }
}
