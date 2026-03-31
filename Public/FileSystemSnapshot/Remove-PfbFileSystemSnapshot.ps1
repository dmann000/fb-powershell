function Remove-PfbFileSystemSnapshot {
    <#
    .SYNOPSIS
        Removes a file system snapshot from the FlashBlade.
    .PARAMETER Name
        The name of the snapshot to remove.
    .PARAMETER Id
        The ID of the snapshot to remove.
    .PARAMETER Eradicate
        Permanently eradicate a destroyed snapshot.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbFileSystemSnapshot -Name "fs1.daily"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [switch]$Eradicate,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($Name) { $Name } else { $Id }
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if (-not $Eradicate) {
            if ($PSCmdlet.ShouldProcess($target, 'Destroy snapshot')) {
                $body = @{ destroyed = $true }
                Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-system-snapshots' -Body $body -QueryParams $queryParams
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($target, 'Eradicate snapshot (PERMANENT)')) {
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-system-snapshots' -QueryParams $queryParams
            }
        }
    }
}
