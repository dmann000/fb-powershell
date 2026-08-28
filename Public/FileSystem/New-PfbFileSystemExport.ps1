function New-PfbFileSystemExport {
    <#
    .SYNOPSIS
        Creates a new file system export on the FlashBlade.
    .DESCRIPTION
        Creates a file system export that makes a file system visible on a server under an
        export policy. Per the FlashBlade REST API, an export links three things:
          - a file system (query parameter 'member_names'),
          - an export policy (query parameter 'policy_names') -- an NFS export policy for NFS,
          - a server, plus (for SMB) an SMB share policy, supplied in the request body.

        This replaces the previous behavior, which incorrectly sent 'names=<export>' and an
        arbitrary body -- the API rejected it, so export creation did not work.
    .PARAMETER FileSystem
        Name of the file system the export exposes. Sent as 'member_names'.
    .PARAMETER Policy
        Name of the export policy to attach (e.g., an NFS export policy). Sent as 'policy_names'.
    .PARAMETER ExportName
        The export name. Must be unique within the same protocol and server.
    .PARAMETER Server
        Name of the server the export will be visible on.
    .PARAMETER SharePolicy
        Name of the SMB share policy (SMB exports only).
    .PARAMETER Attributes
        Optional hashtable merged into the request body for any additional fields.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbFileSystemExport -FileSystem "fs1" -Policy "nfs-default" -ExportName "/fs1" -Server "server1"

        Creates an NFS export of fs1 under the nfs-default export policy on server1.
    .EXAMPLE
        New-PfbFileSystemExport -FileSystem "fs1" -Policy "smb-share" -ExportName "fs1" -Server "server1" -SharePolicy "smb-share"

        Creates an SMB export of fs1 on server1 with the given SMB share policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$FileSystem,

        [Parameter()]
        [string]$Policy,

        [Parameter()]
        [string]$ExportName,

        [Parameter()]
        [string]$Server,

        [Parameter()]
        [string]$SharePolicy,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes.Clone() } else { @{} }
    if ($ExportName)  { $body['export_name']  = $ExportName }
    if ($Server)      { $body['server']       = @{ name = $Server } }
    if ($SharePolicy) { $body['share_policy'] = @{ name = $SharePolicy } }

    $queryParams = @{ 'member_names' = $FileSystem }
    if ($Policy) { $queryParams['policy_names'] = $Policy }

    $target = if ($ExportName) { $ExportName } else { $FileSystem }
    if ($PSCmdlet.ShouldProcess($target, 'Create file system export')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-exports' -Body $body -QueryParams $queryParams
    }
}
