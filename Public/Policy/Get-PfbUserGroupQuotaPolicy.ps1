function Get-PfbUserGroupQuotaPolicy {
    <#
    .SYNOPSIS
        Retrieves user/group quota policies from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbUserGroupQuotaPolicy cmdlet returns user-group-quota policies from the
        connected Pure Storage FlashBlade. These policies define quota rules for users and
        groups across one or more file systems, replacing the legacy per-filesystem
        purequota/purefs quota model.
    .PARAMETER Name
        One or more policy names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more policy IDs to retrieve.
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
        Get-PfbUserGroupQuotaPolicy

        Retrieves all user-group-quota policies.
    .EXAMPLE
        Get-PfbUserGroupQuotaPolicy -Name "quota-pol-1"

        Retrieves the policy named 'quota-pol-1'.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [switch]$TotalOnly,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames.ToArray() -Ids $allIds.ToArray()

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'user-group-quota-policies' -QueryParams $queryParams -AutoPaginate
    }
}
