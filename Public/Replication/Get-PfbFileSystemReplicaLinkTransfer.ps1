function Get-PfbFileSystemReplicaLinkTransfer {
    <#
    .SYNOPSIS
        Retrieves file system replica link transfer information from the FlashBlade.
    .DESCRIPTION
        Returns transfer status and progress for file system replica links, including
        replication direction, data transferred, and completion status. Supports
        filtering by name, ID, or advanced filter expressions. Auto-paginates by default.
    .PARAMETER Name
        One or more replica link names to retrieve transfer status for. Accepts pipeline input.
    .PARAMETER Id
        One or more replica link IDs to retrieve transfer status for.
    .PARAMETER Filter
        A server-side filter expression to narrow results (e.g., "direction='outbound'").
    .PARAMETER Sort
        Sort field and direction (e.g., "progress", "progress-" for descending).
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkTransfer
        Returns transfer status for all file system replica links.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkTransfer -Name "fs01"
        Returns transfer status for the specified replica link.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkTransfer -Filter "direction='outbound'" -Sort "progress"
        Returns outbound transfers sorted by progress.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string[]]$Id,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$Sort,

        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$Limit,

        [Parameter()]
        [switch]$TotalOnly,

        [Parameter()]
        [PSCustomObject]$Array
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
        if ($allNames.Count -gt 0) { $queryParams['names']      = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']        = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter']     = $Filter }
        if ($Sort)                 { $queryParams['sort']       = $Sort }
        if ($Limit -gt 0)         { $queryParams['limit']      = $Limit }
        if ($TotalOnly)            { $queryParams['total_only'] = 'true' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links/transfer' -QueryParams $queryParams -AutoPaginate
    }
}
