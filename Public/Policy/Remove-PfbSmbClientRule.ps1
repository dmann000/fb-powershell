function Remove-PfbSmbClientRule {
    <#
    .SYNOPSIS
        Removes an SMB client policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from an SMB client policy identified by rule name or by
        policy name/ID. This action is irreversible. Use -Confirm:$false to suppress
        the confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the SMB client rule to remove (e.g. 'smb-client-01.1').
    .PARAMETER PolicyName
        The name of the SMB client policy whose rule should be removed.
    .PARAMETER PolicyId
        The ID of the SMB client policy whose rule should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSmbClientRule -Name "smb-client-01.1"

        Removes the SMB client rule by name.
    .EXAMPLE
        Remove-PfbSmbClientRule -Name "smb-client-01.1" -Confirm:$false

        Removes the SMB client rule without confirmation.
    .EXAMPLE
        Remove-PfbSmbClientRule -PolicyName "smb-client-01" -Name "smb-client-01.1"

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

        if ($PSCmdlet.ShouldProcess($Name, 'Remove SMB client rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'smb-client-policies/rules' -QueryParams $queryParams
        }
    }
}
