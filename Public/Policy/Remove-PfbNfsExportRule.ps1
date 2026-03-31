function Remove-PfbNfsExportRule {
    <#
    .SYNOPSIS
        Removes an NFS export policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from an NFS export policy identified by rule name or by
        policy name/ID. This action is irreversible. Use -Confirm:$false to suppress
        the confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the NFS export rule to remove (e.g. 'nfs-export-01.1').
    .PARAMETER PolicyName
        The name of the NFS export policy whose rule should be removed.
    .PARAMETER PolicyId
        The ID of the NFS export policy whose rule should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbNfsExportRule -Name "nfs-export-01.1"

        Removes the NFS export rule by name.
    .EXAMPLE
        Remove-PfbNfsExportRule -Name "nfs-export-01.1" -Confirm:$false

        Removes the NFS export rule without confirmation.
    .EXAMPLE
        Remove-PfbNfsExportRule -PolicyName "nfs-export-01" -Name "nfs-export-01.1"

        Removes a specific rule from the named policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$PolicyName,

        [Parameter()]
        [string]$PolicyId,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
        if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove NFS export rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'nfs-export-policies/rules' -QueryParams $queryParams
        }
    }
}
