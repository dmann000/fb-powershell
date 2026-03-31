function Update-PfbQuotaGroup {
    <#
    .SYNOPSIS
        Updates an existing group quota on a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The Update-PfbQuotaGroup cmdlet modifies the quota limit for an existing group quota
        entry on a FlashBlade file system. You can specify a new quota value in bytes or
        provide a complete attributes hashtable for advanced updates.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system containing the group quota to update.
    .PARAMETER GroupName
        The name of the group whose quota should be updated.
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
        Update-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'marketing' -Quota 5368709120 -Confirm:$false

        Updates the group quota without prompting for confirmation.
    .EXAMPLE
        Update-PfbQuotaGroup -FileSystemName 'fs-nfs01' -GroupName 'ops' -Attributes @{ quota = 0 }

        Removes the quota limit for the 'ops' group by setting it to zero using a custom attributes hashtable.
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
        $body = @{}
        if ($Quota -gt 0) { $body['quota'] = $Quota }
    }
    $q = @{ 'names' = $GroupName; 'file_system_names' = $FileSystemName }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${GroupName}", 'Update group quota')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'quotas/groups' -Body $body -QueryParams $q
    }
}
