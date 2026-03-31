function Remove-PfbAuditFileSystemPolicy {
    <#
    .SYNOPSIS
        Removes an audit file-system policy from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbAuditFileSystemPolicy cmdlet deletes an audit file-system policy from
        the connected Pure Storage FlashBlade. The policy is identified by name or ID.
        This is a destructive operation and requires confirmation.
    .PARAMETER Name
        The name of the audit file-system policy to remove.
    .PARAMETER Id
        The ID of the audit file-system policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbAuditFileSystemPolicy -Name "audit-fs-pol1"

        Removes the audit file-system policy named "audit-fs-pol1" after confirmation.
    .EXAMPLE
        Remove-PfbAuditFileSystemPolicy -Id "12345" -Confirm:$false

        Removes the audit file-system policy by ID without prompting for confirmation.
    .EXAMPLE
        Get-PfbAuditFileSystemPolicy -Name "audit-fs-pol1" | Remove-PfbAuditFileSystemPolicy

        Retrieves and removes the specified audit file-system policy via pipeline.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove audit file-system policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'audit-file-systems-policies' -QueryParams $queryParams
        }
    }
}
