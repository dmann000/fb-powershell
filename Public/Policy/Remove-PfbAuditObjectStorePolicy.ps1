function Remove-PfbAuditObjectStorePolicy {
    <#
    .SYNOPSIS
        Removes an audit object-store policy from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbAuditObjectStorePolicy cmdlet deletes an audit object-store policy from
        the connected Pure Storage FlashBlade. The policy is identified by name or ID.
        This is a destructive operation and requires confirmation.
    .PARAMETER Name
        The name of the audit object-store policy to remove.
    .PARAMETER Id
        The ID of the audit object-store policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAuditObjectStorePolicy -Name "audit-obj-pol1"

        Removes the audit object-store policy named "audit-obj-pol1" after confirmation.
    .EXAMPLE
        Remove-PfbAuditObjectStorePolicy -Id "12345" -Confirm:$false

        Removes the audit object-store policy by ID without prompting for confirmation.
    .EXAMPLE
        Get-PfbAuditObjectStorePolicy -Name "audit-obj-pol1" | Remove-PfbAuditObjectStorePolicy

        Retrieves and removes the specified audit object-store policy via pipeline.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove audit object-store policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'audit-object-store-policies' -QueryParams $queryParams
        }
    }
}
