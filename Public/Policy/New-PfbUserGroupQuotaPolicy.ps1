function New-PfbUserGroupQuotaPolicy {
    <#
    .SYNOPSIS
        Creates a new user/group quota policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbUserGroupQuotaPolicy cmdlet creates a new user-group-quota policy on the
        connected Pure Storage FlashBlade. Either build a policy from scratch with -Enabled/
        -Location/-Rules, or import an existing file system's legacy purequota/purefs quota
        configuration into a new policy by specifying -FileSystemName or -FileSystemId
        (mutually exclusive with each other).
    .PARAMETER Name
        The name for the new policy.
    .PARAMETER FileSystemName
        The name of a file system whose existing legacy quota configuration should be
        imported into this new policy. Mutually exclusive with -FileSystemId.
    .PARAMETER FileSystemId
        The ID of a file system whose existing legacy quota configuration should be imported
        into this new policy. Mutually exclusive with -FileSystemName.
    .PARAMETER Enabled
        Whether the policy is enabled. Defaults to true on the array if not specified.
    .PARAMETER Location
        A hashtable reference to the array where the policy is defined (fleet/realm use).
    .PARAMETER Rules
        An array of rule hashtables to create the policy with (see New-PfbUserGroupQuotaPolicyRule
        for individual rule shape, e.g. @{ subject = @{ name = 'jdoe' }; quota_type = 'user';
        quota_limit = 1073741824 }).
    .PARAMETER Attributes
        A hashtable used verbatim as the request body, overriding -Enabled/-Location/-Rules.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbUserGroupQuotaPolicy -Name "quota-pol-1" -Rules @(@{ subject = @{ name = 'jdoe' }; quota_type = 'user'; quota_limit = 1073741824 })

        Creates a policy with one user quota rule for 'jdoe'.
    .EXAMPLE
        New-PfbUserGroupQuotaPolicy -Name "imported-pol" -FileSystemName "fs-home"

        Creates a new policy by importing 'fs-home''s existing legacy quota configuration.
    .EXAMPLE
        New-PfbUserGroupQuotaPolicy -Name "quota-pol-1" -WhatIf

        Shows what would happen without actually creating the policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [string]$FileSystemName,
        [Parameter()] [string]$FileSystemId,
        [Parameter()] [Nullable[bool]]$Enabled,
        [Parameter()] [hashtable]$Location,
        [Parameter()] [hashtable[]]$Rules,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    if ($FileSystemName -and $FileSystemId) {
        throw '-FileSystemName and -FileSystemId cannot both be specified.'
    }

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
        if ($Location) { $body['location'] = $Location }
        if ($Rules)    { $body['rules']    = $Rules }
    }

    $queryParams = @{ 'names' = $Name }
    if ($FileSystemName) { $queryParams['file_system_names'] = $FileSystemName }
    if ($FileSystemId)   { $queryParams['file_system_ids']   = $FileSystemId }

    if ($PSCmdlet.ShouldProcess($Name, 'Create user-group-quota policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'user-group-quota-policies' -Body $body -QueryParams $queryParams
    }
}
