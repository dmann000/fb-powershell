function Get-PfbObjectStoreRemoteCredential {
    <#
    .SYNOPSIS
        Retrieves object store remote credentials from the FlashBlade.
    .DESCRIPTION
        Returns remote credentials used for object replication to external
        S3-compatible targets. These credentials store the access key and
        secret key for authenticating to remote object stores.
    .PARAMETER Name
        One or more remote credential names to retrieve.
    .PARAMETER Id
        One or more remote credential IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbObjectStoreRemoteCredential
        Returns all remote credentials.
    .EXAMPLE
        Get-PfbObjectStoreRemoteCredential -Name "s3-replication-cred"
        Returns the remote credential named 's3-replication-cred'.
    .EXAMPLE
        Get-PfbObjectStoreRemoteCredential -Filter "name='s3-*'" -Sort "name" -Limit 10
        Returns filtered and sorted remote credentials.
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
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-remote-credentials' -QueryParams $queryParams -AutoPaginate
    }
}
