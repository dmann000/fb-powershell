function Remove-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Removes a group quota from a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The Remove-PfbQuotaGroup cmdlet deletes a group quota entry from the specified file system
        on the FlashBlade. This operation has a high confirm impact and will prompt for confirmation
        by default. Use -Confirm:$false to suppress the prompt.
    .PARAMETER FileSystemName
        The name of the file system containing the group quota to remove.
    .PARAMETER GroupName
        The name of the group whose quota should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'engineering'

        Removes the group quota for 'engineering' on 'fs-nfs01' after prompting for confirmation.
    .EXAMPLE
        Remove-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'temp-team' -Confirm:$false

        Removes the group quota without prompting for confirmation.
    .EXAMPLE
        Remove-PfbQuotaGroup -FileSystemName 'fs-smb01' -GroupName 'contractors' -Array $FlashBlade

        Removes the group quota using a specific FlashBlade connection object.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)] [string]$FileSystemName,
        [Parameter(Mandatory)] [string]$GroupName,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    $q = @{ 'names' = $GroupName; 'file_system_names' = $FileSystemName }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${GroupName}", 'Remove group quota')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'quotas/groups' -QueryParams $q
    }
}
