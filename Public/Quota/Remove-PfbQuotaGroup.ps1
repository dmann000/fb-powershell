function Remove-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Removes a group quota from an Everpure FlashBlade file system.
    .DESCRIPTION
        The Remove-PfbQuotaGroup cmdlet deletes a group quota entry from the specified file system
        on the FlashBlade. Identify the group by name (-GroupName) or numeric GID (-GroupId).
        Identity binds from the pipeline via flattened 'FileSystemName' / 'GroupName' properties
        emitted by Get-PfbQuotaGroup. This operation has a high confirm impact and will prompt for
        confirmation by default. Use -Confirm:$false to suppress the prompt.
    .PARAMETER FileSystemName
        The name of the file system containing the group quota to remove. Binds from pipeline property 'FileSystemName'.
    .PARAMETER GroupName
        The name of the group whose quota should be removed. Mutually exclusive with -GroupId.
        Binds from pipeline property 'GroupName'.
    .PARAMETER GroupId
        The numeric GID of the group whose quota should be removed. Mutually exclusive with -GroupName.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'engineering'

        Removes the group quota for 'engineering' on 'fs-nfs01' after prompting for confirmation.
    .EXAMPLE
        Remove-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupId 1001 -Confirm:$false

        Removes the group quota for GID 1001 without prompting for confirmation.
    .EXAMPLE
        Get-PfbQuotaGroup -FileSystemName 'fs-nfs01' | Remove-PfbQuotaGroup -Confirm:$false

        Removes every group quota on 'fs-nfs01'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$FileSystemName,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ByName')] [string]$GroupName,
        [Parameter(Mandatory, ParameterSetName = 'ById')] [int]$GroupId,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $q = @{ 'group_names' = $GroupName; 'file_system_names' = $FileSystemName }
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $q = @{ 'gids' = $GroupId; 'file_system_names' = $FileSystemName }
        }
        $target = if ($PSCmdlet.ParameterSetName -eq 'ById') { $GroupId } else { $GroupName }
        if ($PSCmdlet.ShouldProcess("${FileSystemName}:${target}", 'Remove group quota')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'quotas/groups' -QueryParams $q
        }
    }
}
