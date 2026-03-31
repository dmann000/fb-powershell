function New-PfbFileSystem {
    <#
    .SYNOPSIS
        Creates a new file system on the FlashBlade.
    .DESCRIPTION
        Creates one or more file systems with the specified configuration.
    .PARAMETER Name
        The name of the file system to create.
    .PARAMETER Provisioned
        The provisioned size in bytes.
    .PARAMETER HardLimitEnabled
        Enable hard limit on provisioned size.
    .PARAMETER NfsEnabled
        Enable NFS protocol access.
    .PARAMETER NfsRules
        NFS export rules (e.g., "*(rw,no_root_squash)").
    .PARAMETER SmbEnabled
        Enable SMB protocol access.
    .PARAMETER HttpEnabled
        Enable HTTP protocol access.
    .PARAMETER SnapshotEnabled
        Enable snapshot directory visibility.
    .PARAMETER Attributes
        A hashtable of additional attributes to set on the file system.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbFileSystem -Name "fs1" -Provisioned 1073741824 -NfsEnabled
    .EXAMPLE
        New-PfbFileSystem -Name "fs1" -Attributes @{ provisioned = 1073741824; nfs = @{ enabled = $true } }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [int64]$Provisioned,

        [Parameter()]
        [switch]$HardLimitEnabled,

        [Parameter()]
        [switch]$NfsEnabled,

        [Parameter()]
        [string]$NfsRules,

        [Parameter()]
        [switch]$SmbEnabled,

        [Parameter()]
        [switch]$HttpEnabled,

        [Parameter()]
        [switch]$SnapshotEnabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    # Build body from individual params or Attributes
    if ($Attributes) {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($Provisioned -gt 0)  { $body['provisioned'] = $Provisioned }
        if ($HardLimitEnabled)   { $body['hard_limit_enabled'] = $true }
        if ($SnapshotEnabled)    { $body['snapshot_directory_enabled'] = $true }

        $nfs = @{}
        if ($NfsEnabled)         { $nfs['v3_enabled'] = $true; $nfs['v4_1_enabled'] = $true }
        if ($NfsRules)           { $nfs['rules'] = $NfsRules }
        if ($nfs.Count -gt 0)    { $body['nfs'] = $nfs }

        if ($SmbEnabled)         { $body['smb'] = @{ enabled = $true } }
        if ($HttpEnabled)        { $body['http'] = @{ enabled = $true } }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create file system')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-systems' -Body $body -QueryParams $queryParams
    }
}
