function Get-PfbS3ExportPolicy {
    <#
    .SYNOPSIS
        Retrieves S3 export policies from the FlashBlade.
    .DESCRIPTION
        Returns one or more S3 export policies from the FlashBlade array.
        S3 export policies control how S3 data is exported and accessed.
        Policies can be filtered by name, ID, or a server-side filter expression.
        Results can be sorted and limited. Supports pipeline input on Name.
    .PARAMETER Name
        One or more S3 export policy names to retrieve.
    .PARAMETER Id
        One or more S3 export policy IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbS3ExportPolicy

        Returns all S3 export policies.
    .EXAMPLE
        Get-PfbS3ExportPolicy -Name "s3-export-01"

        Returns the S3 export policy named 's3-export-01'.
    .EXAMPLE
        "s3-export-01", "s3-export-02" | Get-PfbS3ExportPolicy

        Returns S3 export policies using pipeline input.
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
        if ($allNames.Count -gt 0) { $queryParams['names']  = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']    = $allIds -join ',' }
        if ($Filter)               { $queryParams['filter'] = $Filter }
        if ($Sort)                 { $queryParams['sort']   = $Sort }
        if ($Limit -gt 0)        { $queryParams['limit']  = $Limit }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 's3-export-policies' -QueryParams $queryParams -AutoPaginate
    }
}
