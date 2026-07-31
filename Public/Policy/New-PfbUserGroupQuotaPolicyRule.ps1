function New-PfbUserGroupQuotaPolicyRule {
    <#
    .SYNOPSIS
        Adds a quota rule to a user/group quota policy on a FlashBlade array.
    .DESCRIPTION
        The New-PfbUserGroupQuotaPolicyRule cmdlet adds a new rule to an existing
        user-group-quota policy on the connected Pure Storage FlashBlade. A rule applies a
        quota limit to a specific user or group (-Subject with -QuotaType 'user'/'group'), or
        sets the policy's default for all users/groups (-QuotaType 'user-default'/
        'group-default', which cannot be combined with -Subject).
    .PARAMETER PolicyName
        The name of the policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the policy to add the rule to.
    .PARAMETER Subject
        A hashtable identifying the user or group the rule applies to, e.g. @{ name = 'jdoe' },
        @{ id = 1001 } (UID/GID), or @{ sid = 'S-1-5-...' }. Omit for -QuotaType
        'user-default'/'group-default'.
    .PARAMETER QuotaType
        The rule's quota type: 'user', 'group', 'user-default', or 'group-default'.
    .PARAMETER QuotaLimit
        The quota limit in bytes. Cannot be 0.
    .PARAMETER Enforced
        If true, exceeding the quota is a hard error; if false, it is advisory-only.
    .PARAMETER Notifications
        Whether to notify the affected subject: 'None' or 'Account' (default 'Account').
    .PARAMETER IgnoreUsage
        If set, existing user/group usage is not checked against this rule's quota_limit.
    .PARAMETER Attributes
        A hashtable used verbatim as the request body, overriding -Subject/-QuotaType/
        -QuotaLimit/-Enforced/-Notifications.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbUserGroupQuotaPolicyRule -PolicyName "quota-pol-1" -Subject @{ name = 'jdoe' } -QuotaType user -QuotaLimit 1073741824

        Adds a 1 GiB quota rule for user 'jdoe' to 'quota-pol-1'.
    .EXAMPLE
        New-PfbUserGroupQuotaPolicyRule -PolicyName "quota-pol-1" -QuotaType user-default -QuotaLimit 536870912

        Sets a 512 MiB default quota for all users under 'quota-pol-1'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyName', Mandatory, Position = 0)]
        [string]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId', Mandatory)]
        [string]$PolicyId,

        [Parameter()] [hashtable]$Subject,
        [Parameter()] [ValidateSet('user', 'group', 'user-default', 'group-default')] [string]$QuotaType,
        [Parameter()] [int64]$QuotaLimit,
        [Parameter()] [Nullable[bool]]$Enforced,
        [Parameter()] [ValidateSet('None', 'Account')] [string]$Notifications,
        [Parameter()] [switch]$IgnoreUsage,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($Subject)   { $body['subject']    = $Subject }
        if ($QuotaType) { $body['quota_type'] = $QuotaType }
        if ($PSBoundParameters.ContainsKey('QuotaLimit')) { $body['quota_limit'] = $QuotaLimit }
        if ($PSBoundParameters.ContainsKey('Enforced'))   { $body['enforced']    = [bool]$Enforced }
        if ($Notifications) { $body['notifications'] = $Notifications }
    }

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($IgnoreUsage) { $queryParams['ignore_usage'] = 'true' }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Add user-group-quota policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'user-group-quota-policies/rules' -Body $body -QueryParams $queryParams
    }
}
