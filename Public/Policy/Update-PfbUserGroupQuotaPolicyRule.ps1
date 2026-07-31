function Update-PfbUserGroupQuotaPolicyRule {
    <#
    .SYNOPSIS
        Updates a user/group quota policy rule on a FlashBlade array.
    .DESCRIPTION
        The Update-PfbUserGroupQuotaPolicyRule cmdlet modifies an existing user-group-quota
        policy rule. Only -QuotaLimit and -Notifications can be changed after creation; to
        change a rule's subject or quota type, remove and recreate it.
    .PARAMETER Name
        The name of the rule to update.
    .PARAMETER Id
        The ID of the rule to update.
    .PARAMETER QuotaLimit
        The new quota limit in bytes. Cannot be 0.
    .PARAMETER Notifications
        Whether to notify the affected subject: 'None' or 'Account'.
    .PARAMETER IgnoreUsage
        If set, existing user/group usage is not checked against the new quota_limit.
    .PARAMETER Attributes
        A hashtable used verbatim as the request body, overriding -QuotaLimit/-Notifications.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbUserGroupQuotaPolicyRule -Name "quota-pol-1.1" -QuotaLimit 2147483648
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [int64]$QuotaLimit,
        [Parameter()] [ValidateSet('None', 'Account')] [string]$Notifications,
        [Parameter()] [switch]$IgnoreUsage,
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
            if ($PSBoundParameters.ContainsKey('QuotaLimit')) { $body['quota_limit'] = $QuotaLimit }
            if ($Notifications) { $body['notifications'] = $Notifications }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        if ($IgnoreUsage) { $queryParams['ignore_usage'] = 'true' }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update user-group-quota policy rule')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'user-group-quota-policies/rules' -Body $body -QueryParams $queryParams
        }
    }
}
