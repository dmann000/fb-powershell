function Get-PfbUserGroupQuotaPolicyRule {
    <#
    .SYNOPSIS
        Retrieves user/group quota policy rules from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbUserGroupQuotaPolicyRule cmdlet returns the individual quota rules that
        belong to user-group-quota policies on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        One or more policy names to filter by. Accepts pipeline input.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER Name
        One or more rule names to retrieve.
    .PARAMETER Id
        One or more rule IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbUserGroupQuotaPolicyRule -PolicyName "quota-pol-1"

        Retrieves all rules belonging to the 'quota-pol-1' policy.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId')]
        [string[]]$PolicyId,

        [Parameter()] [string[]]$Name,
        [Parameter()] [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        if ($Name -and $Id) {
            throw 'You cannot supply both -Name and -Id.'
        }
        Assert-PfbConnection -Array ([ref]$Array)
        $allPolicyNames = [System.Collections.Generic.List[string]]::new()
        $allPolicyIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($PolicyName) { foreach ($n in $PolicyName) { $allPolicyNames.Add($n) } }
        if ($PolicyId)   { foreach ($i in $PolicyId)   { $allPolicyIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allPolicyNames.Count -gt 0) { $queryParams['policy_names'] = $allPolicyNames -join ',' }
        if ($allPolicyIds.Count -gt 0)   { $queryParams['policy_ids']   = $allPolicyIds -join ',' }
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $Name -Ids $Id

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'user-group-quota-policies/rules' -QueryParams $queryParams -AutoPaginate
    }
}
