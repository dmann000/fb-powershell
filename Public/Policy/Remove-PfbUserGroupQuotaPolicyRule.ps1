function Remove-PfbUserGroupQuotaPolicyRule {
    <#
    .SYNOPSIS
        Removes one or more user/group quota policy rules from a FlashBlade array.
    .DESCRIPTION
        The Remove-PfbUserGroupQuotaPolicyRule cmdlet deletes rules from a user-group-quota
        policy on the connected Pure Storage FlashBlade. Target specific rules with -Name/-Id,
        or clear every rule belonging to a policy with -PolicyName/-PolicyId alone.
    .PARAMETER Name
        One or more rule names to remove.
    .PARAMETER Id
        One or more rule IDs to remove.
    .PARAMETER PolicyName
        One or more policy names; removes all rules belonging to these policies.
    .PARAMETER PolicyId
        One or more policy IDs; removes all rules belonging to these policies.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbUserGroupQuotaPolicyRule -Name "quota-pol-1.1"
    .EXAMPLE
        Remove-PfbUserGroupQuotaPolicyRule -PolicyName "quota-pol-1"

        Removes every rule belonging to 'quota-pol-1'.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter()] [string[]]$Name,
        [Parameter()] [string[]]$Id,
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if (-not $Name -and -not $Id -and -not $PolicyName -and -not $PolicyId) {
        throw 'You must supply at least one of -Name, -Id, -PolicyName, or -PolicyId.'
    }

    $queryParams = @{}
    if ($Name)       { $queryParams['names']        = $Name -join ',' }
    if ($Id)         { $queryParams['ids']          = $Id -join ',' }
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId -join ',' }

    $target = if ($Name) { $Name -join ',' } elseif ($Id) { $Id -join ',' } elseif ($PolicyName) { "policy:$($PolicyName -join ',')" } else { "policy:$($PolicyId -join ',')" }

    if ($PSCmdlet.ShouldProcess($target, 'Remove user-group-quota policy rule')) {
        Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'user-group-quota-policies/rules' -QueryParams $queryParams
    }
}
