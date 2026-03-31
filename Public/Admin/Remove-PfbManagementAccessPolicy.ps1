function Remove-PfbManagementAccessPolicy {
    <#
    .SYNOPSIS
        Removes a management access policy from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbManagementAccessPolicy cmdlet deletes a management access policy from the
        connected Pure Storage FlashBlade. The target policy can be identified by name or ID.
        This is a destructive operation and requires confirmation by default.
    .PARAMETER Name
        The name of the management access policy to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the management access policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbManagementAccessPolicy -Name "ops-policy"

        Removes the management access policy named "ops-policy".
    .EXAMPLE
        Remove-PfbManagementAccessPolicy -Id "abc12345-6789-0abc-def0-123456789abc" -Confirm:$false

        Removes the management access policy without confirmation.
    .EXAMPLE
        "test-policy" | Remove-PfbManagementAccessPolicy

        Removes the management access policy via pipeline input.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove management access policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'management-access-policies' -QueryParams $queryParams
        }
    }
}
