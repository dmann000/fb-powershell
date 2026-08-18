function Remove-PfbResourceAccess {
    <#
    .SYNOPSIS
        Removes a resource access entry from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbResourceAccess cmdlet deletes a resource access entry from the connected
        Pure Storage FlashBlade. The entry is identified by its ID.
    .PARAMETER Id
        The ID of the resource access to remove. Binds from the pipeline by property
        name, so resource access objects (which carry 'id') can be piped in directly.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbResourceAccess -Id "10314f42-020d-7080-8013-000ddt400012"

        Removes the resource access entry after prompting for confirmation.
    .EXAMPLE
        Remove-PfbResourceAccess -Id "10314f42-020d-7080-8013-000ddt400012" -Confirm:$false

        Removes the resource access entry without prompting.
    .EXAMPLE
        Get-PfbResourceAccess | Where-Object { $_.scope.name -eq 'admin' } | Remove-PfbResourceAccess -Confirm:$false

        Removes every matching resource access entry, one DELETE per piped object;
        -Id binds from each object's 'id' property.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$Id,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Id) { $queryParams['ids'] = $Id }
        if ($PSCmdlet.ShouldProcess($Id, 'Remove resource access')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'resource-accesses' -QueryParams $queryParams
        }
    }
}
