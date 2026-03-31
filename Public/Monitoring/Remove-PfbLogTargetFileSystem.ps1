function Remove-PfbLogTargetFileSystem {
    <#
    .SYNOPSIS
        Removes a log-target file-system configuration from the FlashBlade.
    .DESCRIPTION
        The Remove-PfbLogTargetFileSystem cmdlet deletes a log-target file-system
        configuration from the connected Pure Storage FlashBlade. The target is identified
        by name or ID. This is a destructive operation and requires confirmation.
    .PARAMETER Name
        The name of the log-target file system to remove.
    .PARAMETER Id
        The ID of the log-target file system to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbLogTargetFileSystem -Name "log-fs-target1"

        Removes the log-target file-system configuration named "log-fs-target1".
    .EXAMPLE
        Remove-PfbLogTargetFileSystem -Id "12345" -Confirm:$false

        Removes the log-target file system by ID without prompting for confirmation.
    .EXAMPLE
        Get-PfbLogTargetFileSystem -Name "log-fs-target1" | Remove-PfbLogTargetFileSystem

        Retrieves and removes the specified log-target file system via pipeline.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Remove log-target file system')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'log-targets/file-systems' -QueryParams $queryParams
        }
    }
}
