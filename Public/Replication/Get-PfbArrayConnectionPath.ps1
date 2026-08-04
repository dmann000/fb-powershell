function Get-PfbArrayConnectionPath {
    <#
    .SYNOPSIS
        Retrieves array connection path information from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbArrayConnectionPath cmdlet returns network path information for array
        connections on the connected Everpure FlashBlade.

        An array connection has no name of its own -- the API resource carries only an id. Its
        human-readable identifier is the REMOTE array's name, so -RemoteName (aliased to -Name
        for compatibility) is how you select one by name.
    .PARAMETER RemoteName
        One or more REMOTE array names whose connection paths to retrieve. Aliased to -Name.
        Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "id" or "id-"). An array connection path has no name
        field, so "name" is not a valid sort field here -- use "id", "status" or "type".
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArrayConnectionPath

        Retrieves all array connection paths from the connected FlashBlade.
    .EXAMPLE
        Get-PfbArrayConnectionPath -RemoteName "FB-B"

        Retrieves connection paths for the specified remote array.
    .EXAMPLE
        Get-PfbArrayConnectionPath -Limit 10

        Retrieves up to 10 array connection paths.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]$RemoteName,

        [Parameter()] [string]$Filter, [Parameter()] [string]$Sort, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )
    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allRemoteNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($RemoteName) {
            foreach ($n in $RemoteName) {
                # This cmdlet has no -Id parameter, so a piped array-connection object falls
                # through PowerShell's ByValue-with-coercion pass and gets ToString()-ed into
                # -RemoteName (issue #64 follow-up). Fail here with an actionable message rather
                # than sending remote_names=@{...} and letting the array reject it.
                Assert-PfbRemoteNameNotCoerced -Value $n
                $allRemoteNames.Add($n)
            }
        }
    }

    end {
        $queryParams = @{}
        # No -Names argument: GET /array-connections/path documents no names parameter in any
        # spec version, and an unrecognised key is silently ignored rather than rejected, so the
        # old call returned every path unfiltered (issue #64). remote_names is assigned inline
        # for the reason given in Get-PfbArrayConnection.ps1.
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters
        if ($allRemoteNames.Count) { $queryParams['remote_names'] = $allRemoteNames -join ',' }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'array-connections/path' -QueryParams $queryParams -AutoPaginate
    }
}
