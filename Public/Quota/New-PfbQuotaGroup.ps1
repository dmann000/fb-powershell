function New-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Creates a new group quota on an Everpure FlashBlade file system.
    .DESCRIPTION
        The New-PfbQuotaGroup cmdlet creates a group quota entry that limits the amount of
        storage a specific group can consume on a given file system. Identify the group by name
        (-GroupName) or numeric GID (-GroupId). Specify exactly one. You can set the quota size
        in bytes with -Quota or provide a complete body hashtable with -Attributes for advanced use.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system on which to create the group quota.
    .PARAMETER GroupName
        The name of the group to apply the quota to. Mutually exclusive with -GroupId.
    .PARAMETER GroupId
        The numeric GID of the group to apply the quota to. Mutually exclusive with -GroupName.
    .PARAMETER Quota
        The quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, it overrides the body built
        from -Quota. The group/file-system identity is always taken from the other parameters
        and sent as query parameters, not from this hashtable.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'engineering' -Quota 10737418240

        Creates a 10 GiB group quota for the 'engineering' group on 'fs-nfs01'.
    .EXAMPLE
        New-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupId 1001 -Quota 5368709120

        Creates a 5 GiB group quota for GID 1001 on 'fs-nfs01'.
    .EXAMPLE
        New-PfbQuotaGroup -FileSystemName 'fs-smb01' -GroupName 'finance' -Attributes @{ quota = 21474836480 }

        Creates a group quota using a custom attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory)] [string]$FileSystemName,
        [Parameter(Mandatory, ParameterSetName = 'ByName')] [string]$GroupName,
        [Parameter(Mandatory, ParameterSetName = 'ById')] [int]$GroupId,
        [Parameter()] [int64]$Quota,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        if ($Quota -le 0) {
            throw 'Provide -Quota (a positive value) or -Attributes to specify the quota body.'
        }
        $body = @{ quota = $Quota }
    }

    $q = @{ 'file_system_names' = $FileSystemName }
    if ($GroupName) { $q['group_names'] = $GroupName }
    if ($PSBoundParameters.ContainsKey('GroupId')) { $q['gids'] = $GroupId }

    $target = if ($GroupName) { $GroupName } else { $GroupId }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${target}", 'Create group quota')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'quotas/groups' -Body $body -QueryParams $q
    }
}
