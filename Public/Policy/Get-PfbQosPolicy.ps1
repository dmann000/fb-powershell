function Get-PfbQosPolicy {
    <#
    .SYNOPSIS
        Retrieves QoS policies from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbQosPolicy cmdlet returns Quality of Service policy configurations from
        the connected Pure Storage FlashBlade. QoS policies define bandwidth and IOPS limits
        for file systems and buckets.
    .PARAMETER Name
        One or more QoS policy names to retrieve. Accepts pipeline input.
    .PARAMETER Id
        One or more QoS policy IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "name" or "name-").
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbQosPolicy

        Retrieves all QoS policies from the connected FlashBlade.
    .EXAMPLE
        Get-PfbQosPolicy -Name "qos-gold"

        Retrieves the QoS policy named "qos-gold".
    .EXAMPLE
        Get-PfbQosPolicy -Filter "enabled='true'" -Sort "name" -Limit 10

        Retrieves up to 10 enabled QoS policies sorted by name.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0) { $queryParams['ids'] = $allIds -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        if ($Sort) { $queryParams['sort'] = $Sort }
        if ($Limit -gt 0) { $queryParams['limit'] = $Limit }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'qos-policies' -QueryParams $queryParams -AutoPaginate
    }
}
