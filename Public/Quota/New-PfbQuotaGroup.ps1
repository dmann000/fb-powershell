function New-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Creates a new group quota on a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The New-PfbQuotaGroup cmdlet creates a group quota entry that limits the amount of
        storage a specific group can consume on a given file system. You can specify the quota
        size in bytes or provide a complete attributes hashtable for advanced configurations.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system on which to create the group quota.
    .PARAMETER GroupName
        The name of the group to apply the quota to.
    .PARAMETER Quota
        The quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, FileSystemName, GroupName, and Quota parameters are ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'engineering' -Quota 10737418240

        Creates a 10 GiB group quota for the 'engineering' group on 'fs-nfs01'.
    .EXAMPLE
        New-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'marketing' -Quota 5368709120 -WhatIf

        Shows what would happen when creating a 5 GiB group quota without actually creating it.
    .EXAMPLE
        New-PfbQuotaGroup -FileSystemName 'fs-smb01' -GroupName 'finance' -Attributes @{ group = @{ name = 'finance' }; file_system = @{ name = 'fs-smb01' }; quota = 21474836480 }

        Creates a group quota using a custom attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string]$FileSystemName,
        [Parameter(Mandatory)] [string]$GroupName,
        [Parameter()] [int64]$Quota,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{ group = @{ name = $GroupName }; file_system = @{ name = $FileSystemName } }
        if ($Quota -gt 0) { $body['quota'] = $Quota }
    }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${GroupName}", 'Create group quota')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'quotas/groups' -Body $body
    }
}
