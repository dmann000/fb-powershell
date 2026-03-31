function New-PfbLogTargetFileSystem {
    <#
    .SYNOPSIS
        Creates a new log-target file-system configuration on the FlashBlade.
    .DESCRIPTION
        The New-PfbLogTargetFileSystem cmdlet creates a log-target file-system configuration
        on the connected Pure Storage FlashBlade. Use the Attributes parameter to supply a
        hashtable of configuration properties, or provide individual parameters.
    .PARAMETER Name
        The name of the log-target file system to create.
    .PARAMETER Attributes
        A hashtable of additional attributes for the configuration body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbLogTargetFileSystem -Name "log-fs-target1"

        Creates a new log-target file-system configuration named "log-fs-target1".
    .EXAMPLE
        New-PfbLogTargetFileSystem -Name "log-fs-target1" -Attributes @{ file_system = @{ name = 'audit-fs' } }

        Creates a log-target file-system configuration with custom attributes.
    .EXAMPLE
        New-PfbLogTargetFileSystem -Name "log-fs-target1" -Attributes @{ path = '/audit-logs' }

        Creates a log-target file system with a specific path.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create log-target file system')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'log-targets/file-systems' -Body $body -QueryParams $queryParams
    }
}
