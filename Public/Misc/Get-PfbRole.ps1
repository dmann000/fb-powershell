function Get-PfbRole {
    <#
    .SYNOPSIS
        Retrieves FlashBlade administrator roles.
    .DESCRIPTION
        Returns the available administrator roles configured on the FlashBlade array.
        Roles define the set of permissions granted to administrator accounts.
    .PARAMETER Name
        One or more role names to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbRole

        Retrieves all roles on the FlashBlade.
    .EXAMPLE
        Get-PfbRole -Name "readonly"

        Retrieves the role named 'readonly'.
    .EXAMPLE
        Get-PfbRole -Limit 5

        Retrieves up to 5 roles from the FlashBlade.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'roles' -QueryParams $queryParams -AutoPaginate
    }
}
