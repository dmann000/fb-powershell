function Get-PfbDirectoryService {
    <#
    .SYNOPSIS
        Retrieves FlashBlade directory service configuration (LDAP/NIS/AD).
    .DESCRIPTION
        The Get-PfbDirectoryService cmdlet returns directory service configurations from the
        connected Pure Storage FlashBlade. Directory services control how the array integrates
        with external identity providers for NFS, SMB, and management authentication.
        Supports pipeline input and server-side filtering.
    .PARAMETER Name
        One or more directory service names to retrieve (e.g., 'nfs', 'smb', 'management').
        Accepts pipeline input.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbDirectoryService

        Retrieves all directory service configurations from the connected FlashBlade.
    .EXAMPLE
        Get-PfbDirectoryService -Name "nfs"

        Retrieves the NFS directory service configuration.
    .EXAMPLE
        "nfs", "smb" | Get-PfbDirectoryService

        Retrieves the NFS and SMB directory service configurations via pipeline input.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [string[]]$Name,
        [Parameter()] [string]$Filter,
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
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($Filter) { $queryParams['filter'] = $Filter }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'directory-services' -QueryParams $queryParams -AutoPaginate
    }
}
