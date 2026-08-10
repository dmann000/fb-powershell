function Get-PfbFileSystemReplicaLinkTransfer {
    <#
    .SYNOPSIS
        Retrieves file system replica link transfer information from the FlashBlade.
    .DESCRIPTION
        Returns transfer status and progress for file system replica links, including
        replication direction, data transferred, and completion status. Supports
        filtering by snapshot name, owning file-system name, ID, or advanced filter
        expressions. Auto-paginates by default.

        The API's names_or_owner_names query parameter matches either the names of the
        snapshots or the names of their owning file systems. The resource has no plain
        name selector for this endpoint, so -NameOrOwnerName (aliased to -Name for
        backward compatibility) is used for both cases.
    .PARAMETER NameOrOwnerName
        One or more snapshot names or owning file-system names to retrieve transfer
        status for. Sent as the names_or_owner_names query parameter. Accepts pipeline
        input. Aliased to -Name for backward compatibility.
    .PARAMETER Id
        One or more replica link transfer IDs to retrieve transfer status for. Accepts
        pipeline input by property name.
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
        Get-PfbFileSystemReplicaLinkTransfer -NameOrOwnerName "fs01"

        Returns transfers for snapshots belonging to the file system named "fs01".
        The same parameter can match a snapshot name instead.
    .EXAMPLE
        Get-PfbFileSystemReplicaLinkTransfer -Filter "direction='outbound'" -Sort "progress"

        Returns outbound transfers sorted by progress.
    .EXAMPLE
        Get-PfbFileSystemReplicaLink | Get-PfbFileSystemReplicaLinkTransfer

        Retrieves transfer status for the replica-link transfers identified by the
        IDs in piped replica-link objects.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByNameOrOwnerName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [ValidateNotNullOrEmpty()]
        [string[]]$NameOrOwnerName,

        [Parameter(ParameterSetName = 'ById', ValueFromPipelineByPropertyName)]
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
        if ($NameOrOwnerName) {
            foreach ($n in $NameOrOwnerName) {
                Assert-PfbFileSystemReplicaLinkTransferNameNotCoerced -Value $n
                $allNames.Add($n)
            }
        }
        if ($Id) { foreach ($i in $Id) { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        # names_or_owner_names is an endpoint-specific selector. The common helper only
        # knows the generic names key, which this endpoint does not declare.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        if ($allNames.Count) { $queryParams['names_or_owner_names'] = $allNames -join ',' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links/transfer' -QueryParams $queryParams -AutoPaginate
    }
}
