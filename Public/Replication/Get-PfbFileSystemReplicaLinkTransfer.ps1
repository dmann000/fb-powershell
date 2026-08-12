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
    .PARAMETER RemoteName
        One or more REMOTE ARRAY names whose transfers to retrieve. Composes with either
        selector set. Mutually exclusive with -RemoteId: the API declares remote_names and
        remote_ids as alternative ways to name the same remote dimension.
    .PARAMETER RemoteId
        One or more REMOTE ARRAY IDs whose transfers to retrieve. Composes with either selector
        set. Mutually exclusive with -RemoteName.
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

        # The remote-array dimension is orthogonal to the existing selector sets, so
        # -RemoteName and -RemoteId stay out of them and remain usable alongside either. The
        # spec forbids only their combination with each other, which is enforced at runtime in
        # begin{} rather than by two more parameter sets: putting them in exclusive sets would
        # split every existing set in two and make -Name/-Id resolution ambiguous.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$RemoteName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]$RemoteId,

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
        if ($PSBoundParameters.ContainsKey('RemoteName') -and $PSBoundParameters.ContainsKey('RemoteId')) {
            throw '-RemoteName and -RemoteId cannot be used together: remote_names and remote_ids are mutually exclusive.'
        }
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
        # remote_names and remote_ids are assigned inline for the reason given in
        # Get-PfbArrayConnection.ps1: they are replication-family keys, not common ones.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Ids $allIds
        if ($allNames.Count) { $queryParams['names_or_owner_names'] = $allNames -join ',' }
        if ($RemoteName) { $queryParams['remote_names'] = $RemoteName -join ',' }
        if ($RemoteId)   { $queryParams['remote_ids']   = $RemoteId   -join ',' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-system-replica-links/transfer' -QueryParams $queryParams -AutoPaginate
    }
}
