function Get-PfbObjectStoreAccountExport {
    <#
    .SYNOPSIS
        Retrieves object store account exports from the FlashBlade.
    .DESCRIPTION
        Returns object store account export configurations that control how
        object store accounts are exposed through NFS or other export protocols.
    .PARAMETER Name
        One or more export names to retrieve.
    .PARAMETER Id
        One or more export IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Get-PfbObjectStoreAccountExport
        Returns all object store account exports.
    .EXAMPLE
        Get-PfbObjectStoreAccountExport -Name "export1"
        Returns the specified account export.
    .EXAMPLE
        Get-PfbObjectStoreAccountExport -Filter "name='backup-*'" -Sort "name" -Limit 50
        Returns filtered and sorted account exports.
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'object-store-account-exports' -QueryParams $queryParams -AutoPaginate
    }
}
