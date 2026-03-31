function Remove-PfbSmbShareRule {
    <#
    .SYNOPSIS
        Removes an SMB share policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from an SMB share policy identified by rule name or by
        policy name/ID. This action is irreversible. Use -Confirm:$false to suppress
        the confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the SMB share rule to remove (e.g. 'smb-share-01.1').
    .PARAMETER PolicyName
        The name of the SMB share policy whose rule should be removed.
    .PARAMETER PolicyId
        The ID of the SMB share policy whose rule should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSmbShareRule -Name "smb-share-01.1"

        Removes the SMB share rule by name.
    .EXAMPLE
        Remove-PfbSmbShareRule -Name "smb-share-01.1" -Confirm:$false

        Removes the SMB share rule without confirmation.
    .EXAMPLE
        Remove-PfbSmbShareRule -PolicyName "smb-share-01" -Name "smb-share-01.1"

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

        if ($PSCmdlet.ShouldProcess($Name, 'Remove SMB share rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'smb-share-policies/rules' -QueryParams $queryParams
        }
    }
}
