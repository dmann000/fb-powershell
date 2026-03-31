function Update-PfbQuotaUser {
    <#
    .SYNOPSIS
        Updates an existing user quota on a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The Update-PfbQuotaUser cmdlet modifies the quota limit for an existing user quota
        entry on a FlashBlade file system. You can specify a new quota value in bytes or
        provide a complete attributes hashtable for advanced updates.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system containing the user quota to update.
    .PARAMETER UserName
        The name of the user whose quota should be updated.
    .PARAMETER Quota
        The new quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, the Quota parameter is ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe' -Quota 10737418240

        Increases the user quota for 'jdoe' on 'fs-home' to 10 GiB.
    .EXAMPLE
        Update-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'asmith' -Quota 2147483648 -WhatIf

        Shows what would happen when updating the quota without actually applying the change.
    .EXAMPLE
        Update-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'bwilson' -Attributes @{ quota = 0 }

        Removes the quota limit for user 'bwilson' by setting it to zero using a custom attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [string]$FileSystemName,
        [Parameter(Mandatory)] [string]$UserName,
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
    $q = @{ 'names' = $UserName; 'file_system_names' = $FileSystemName }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${UserName}", 'Update user quota')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'quotas/users' -Body $body -QueryParams $q
    }
}
