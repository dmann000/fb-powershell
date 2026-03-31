function Remove-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Removes an Active Directory configuration from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbActiveDirectory cmdlet deletes an Active Directory configuration from the
        connected Pure Storage FlashBlade, effectively unjoining the array from the domain.
        The target configuration can be identified by name or ID. This cmdlet has a high confirm
        impact and will prompt for confirmation by default. Supports pipeline input.
    .PARAMETER Name
        The name of the Active Directory configuration to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the Active Directory configuration to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbActiveDirectory -Name "ad1"

        Removes the Active Directory configuration named "ad1" after prompting for confirmation.
    .EXAMPLE
        Remove-PfbActiveDirectory -Name "ad-test" -Confirm:$false

        Removes the Active Directory configuration named "ad-test" without prompting.
    .EXAMPLE
        Get-PfbActiveDirectory | Remove-PfbActiveDirectory

        Removes all Active Directory configurations via pipeline input.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove Active Directory')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'active-directory' -QueryParams $queryParams
        }
    }
}
