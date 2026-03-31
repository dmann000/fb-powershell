function Update-PfbLogTargetFileSystem {
    <#
    .SYNOPSIS
        Updates a log-target file-system configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLogTargetFileSystem cmdlet modifies a log-target file-system
        configuration on the connected Pure Storage FlashBlade. Identify the target by
        name or ID and supply the changed properties via Attributes.
    .PARAMETER Name
        The name of the log-target file system to update.
    .PARAMETER Id
        The ID of the log-target file system to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLogTargetFileSystem -Name "log-fs-target1" -Attributes @{ path = '/new-path' }

        Updates the path on the log-target file-system configuration.
    .EXAMPLE
        Update-PfbLogTargetFileSystem -Id "12345" -Attributes @{ enabled = $true }

        Enables the log-target file system identified by ID.
    .EXAMPLE
        Update-PfbLogTargetFileSystem -Name "log-fs-target1" -Attributes @{ file_system = @{ name = 'new-fs' } }

        Updates the underlying file system reference.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $body = if ($Attributes) { $Attributes } else { @{} }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update log-target file system')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'log-targets/file-systems' -Body $body -QueryParams $queryParams
        }
    }
}
