function Update-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Updates an existing group quota on an Everpure FlashBlade file system.
    .DESCRIPTION
        The Update-PfbQuotaGroup cmdlet modifies the quota limit for an existing group quota
        entry on a FlashBlade file system. Identify the group by name (-GroupName) or numeric
        GID (-GroupId). Identity binds from the pipeline via flattened 'FileSystemName' / 'GroupName'
        properties emitted by Get-PfbQuotaGroup. You can specify a new quota value in bytes or
        provide a complete attributes hashtable for advanced updates.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system containing the group quota to update. Binds from pipeline property 'FileSystemName'.
    .PARAMETER GroupName
        The name of the group whose quota should be updated. Mutually exclusive with -GroupId.
        Binds from pipeline property 'GroupName'.
    .PARAMETER GroupId
        The numeric GID of the group whose quota should be updated. Mutually exclusive with -GroupName.
    .PARAMETER Quota
        The new quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, the Quota parameter is ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'engineering' -Quota 21474836480

        Increases the group quota for 'engineering' on 'fs-nfs01' to 20 GiB.
    .EXAMPLE
        Update-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupId 1001 -Quota 5368709120 -Confirm:$false

        Updates the group quota for GID 1001 without prompting for confirmation.
    .EXAMPLE
        Get-PfbQuotaGroup -FileSystemName 'fs-nfs01' | Update-PfbQuotaGroup -Quota 0

        Clears the quota limit for every group quota on 'fs-nfs01'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)] [string]$FileSystemName,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ByName')] [string]$GroupName,
        [Parameter(Mandatory, ParameterSetName = 'ById')] [int]$GroupId,
        [Parameter()] [int64]$Quota,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($Quota -gt 0) { $body['quota'] = $Quota }
        }
        $q = @{ 'group_names' = $GroupName; 'file_system_names' = $FileSystemName }
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $q = @{ 'gids' = $GroupId; 'file_system_names' = $FileSystemName }
        }
        $target = if ($PSCmdlet.ParameterSetName -eq 'ById') { $GroupId } else { $GroupName }
        if ($PSCmdlet.ShouldProcess("${FileSystemName}:${target}", 'Update group quota')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'quotas/groups' -Body $body -QueryParams $q
        }
    }
}
