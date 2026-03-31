function New-PfbQuotaUser {
    <#
    .SYNOPSIS
        Creates a new user quota on a Pure Storage FlashBlade file system.
    .DESCRIPTION
        The New-PfbQuotaUser cmdlet creates a user quota entry that limits the amount of
        storage a specific user can consume on a given file system. You can specify the quota
        size in bytes or provide a complete attributes hashtable for advanced configurations.
        This cmdlet supports the ShouldProcess pattern for -WhatIf and -Confirm.
    .PARAMETER FileSystemName
        The name of the file system on which to create the user quota.
    .PARAMETER UserName
        The name of the user to apply the quota to.
    .PARAMETER Quota
        The quota limit in bytes. For example, 1073741824 equals 1 GiB.
    .PARAMETER Attributes
        A hashtable containing the full request body. When specified, FileSystemName, UserName, and Quota parameters are ignored.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'jdoe' -Quota 5368709120

        Creates a 5 GiB user quota for user 'jdoe' on 'fs-home'.
    .EXAMPLE
        New-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'asmith' -Quota 10737418240 -WhatIf

        Shows what would happen when creating a 10 GiB user quota without actually creating it.
    .EXAMPLE
        New-PfbQuotaUser -FileSystemName 'fs-home' -UserName 'bwilson' -Attributes @{ user = @{ name = 'bwilson' }; file_system = @{ name = 'fs-home' }; quota = 2147483648 }

        Creates a user quota using a custom attributes hashtable.
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
        $body = @{ user = @{ name = $UserName }; file_system = @{ name = $FileSystemName } }
        if ($Quota -gt 0) { $body['quota'] = $Quota }
    }
    if ($PSCmdlet.ShouldProcess("${FileSystemName}:${UserName}", 'Create user quota')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'quotas/users' -Body $body
    }
}
