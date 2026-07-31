function Update-PfbUserGroupQuotaPolicy {
    <#
    .SYNOPSIS
        Updates an existing user/group quota policy on a FlashBlade array.
    .PARAMETER Name
        The name of the policy to update.
    .PARAMETER Id
        The ID of the policy to update.
    .PARAMETER Enabled
        Enable or disable the policy.
    .PARAMETER Location
        A hashtable reference to the array where the policy is defined (fleet/realm use).
    .PARAMETER Rules
        Replaces the policy's rules with this array of rule hashtables.
    .PARAMETER IgnoreUsage
        If set, user/group usage is not checked against the rules' quota_limits.
    .PARAMETER Version
        One or more version tags for optimistic concurrency control. Fails with a 412 if the
        resource's current version doesn't match.
    .PARAMETER Attributes
        A hashtable used verbatim as the request body, overriding -Enabled/-Location/-Rules.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbUserGroupQuotaPolicy -Name "quota-pol-1" -Enabled:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateScript({ Assert-PfbSafeName $_ })]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [Nullable[bool]]$Enabled,
        [Parameter()] [hashtable]$Location,
        [Parameter()] [hashtable[]]$Rules,
        [Parameter()] [switch]$IgnoreUsage,
        [Parameter()] [string[]]$Version,
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
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
            if ($Location) { $body['location'] = $Location }
            if ($Rules)    { $body['rules']    = $Rules }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        if ($IgnoreUsage) { $queryParams['ignore_usage'] = 'true' }
        if ($Version) { $queryParams['versions'] = $Version -join ',' }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update user-group-quota policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'user-group-quota-policies' -Body $body -QueryParams $queryParams
        }
    }
}
