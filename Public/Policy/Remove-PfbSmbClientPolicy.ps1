function Remove-PfbSmbClientPolicy {
    <#
    .SYNOPSIS
        Removes an SMB client policy from the FlashBlade.
    .DESCRIPTION
        Deletes an SMB client policy identified by name or ID from the FlashBlade.
        This action is irreversible. Use -Confirm:$false to suppress the confirmation
        prompt in automation scenarios.
    .PARAMETER Name
        The name of the SMB client policy to remove.
    .PARAMETER Id
        The ID of the SMB client policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbSmbClientPolicy -Name "smb-client-01"

        Removes the SMB client policy named 'smb-client-01'.
    .EXAMPLE
        Remove-PfbSmbClientPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the SMB client policy by ID.
    .EXAMPLE
        Remove-PfbSmbClientPolicy -Name "smb-client-01" -Confirm:$false

        Removes the SMB client policy without confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove SMB client policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'smb-client-policies' -QueryParams $queryParams
        }
    }
}
