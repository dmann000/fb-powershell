function Remove-PfbResourceAccess {
    <#
    .SYNOPSIS
        Removes a resource access entry from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbResourceAccess cmdlet deletes a resource access entry from the connected
        Pure Storage FlashBlade. The entry can be identified by name or ID.
    .PARAMETER Name
        The name of the resource access to remove. Accepts pipeline input.
    .PARAMETER Id
        The ID of the resource access to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbResourceAccess -Name "access-old"

        Removes the resource access entry after prompting for confirmation.
    .EXAMPLE
        Remove-PfbResourceAccess -Name "access-test" -Confirm:$false

        Removes the resource access entry without prompting.
    .EXAMPLE
        Remove-PfbResourceAccess -Id "10314f42-020d-7080-8013-000ddt400012"

        Removes the resource access entry by ID.
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
        if ($PSCmdlet.ShouldProcess($target, 'Remove resource access')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'resource-accesses' -QueryParams $queryParams
        }
    }
}
