function Get-PfbFileSystemSession {
    <#
    .SYNOPSIS
        Retrieves file system sessions from the FlashBlade.
    .DESCRIPTION
        Returns active client sessions connected to file systems on the FlashBlade.
        Supports filtering by session name, protocol, or advanced filter expressions.
        Auto-paginates by default.
    .PARAMETER Name
        One or more session names to filter by -- the session's own generated identifier
        (e.g. as returned in a prior Get-PfbFileSystemSession call's Name property), NOT the
        name of a file system. Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction.
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER TotalOnly
        Return only the total count, not the items.
    .PARAMETER Protocol
        Restricts results to sessions using one or more specific protocols. Valid values are
        "nfs" and "smb".
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Get-PfbFileSystemSession
        Returns all file system sessions on the FlashBlade.
    .EXAMPLE
        Get-PfbFileSystemSession -Name "22517998136858346-smb"
        Returns the single session with that session name.
    .EXAMPLE
        Get-PfbFileSystemSession -Filter "protocol='NFS'" -Limit 50
        Returns up to 50 NFS sessions.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Name,

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
        [ValidateSet('nfs', 'smb')]
        [string[]]$Protocol,

        [Parameter()]
        [PSCustomObject]$Array
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
        if ($Protocol)             { $queryParams['protocols']  = $Protocol -join ',' }

        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'file-systems/sessions' -QueryParams $queryParams -AutoPaginate
    }
}
