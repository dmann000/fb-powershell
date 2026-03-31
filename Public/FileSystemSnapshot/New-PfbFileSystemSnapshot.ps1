function New-PfbFileSystemSnapshot {
    <#
    .SYNOPSIS
        Creates a snapshot of a file system.
    .PARAMETER SourceName
        The name of the source file system to snapshot.
    .PARAMETER Suffix
        An optional suffix for the snapshot name.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbFileSystemSnapshot -SourceName "fs1"
    .EXAMPLE
        New-PfbFileSystemSnapshot -SourceName "fs1" -Suffix "daily"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$SourceName,

        [Parameter()]
        [string]$Suffix,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{
        'source_names' = $SourceName -join ','
    }
    if ($Suffix) { $queryParams['suffix'] = $Suffix }

    if ($PSCmdlet.ShouldProcess(($SourceName -join ', '), 'Create file system snapshot')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-snapshots' -QueryParams $queryParams
    }
}
