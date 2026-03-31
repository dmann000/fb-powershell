function Remove-PfbFileSystem {
    <#
    .SYNOPSIS
        Removes (destroys or eradicates) a file system from the FlashBlade.
    .DESCRIPTION
        Destroys a file system (soft delete) or eradicates a previously destroyed file system
        (permanent delete). Destroyed file systems can be recovered within 24 hours using
        Update-PfbFileSystem -Name "fs1" -Destroyed $false.
    .PARAMETER Name
        The name of the file system to remove.
    .PARAMETER Id
        The ID of the file system to remove.
    .PARAMETER Eradicate
        Permanently eradicate a destroyed file system. Cannot be undone.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbFileSystem -Name "fs1"
    .EXAMPLE
        Remove-PfbFileSystem -Name "fs1" -Eradicate
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
            # Soft delete: first disable all protocols, then PATCH destroyed = true
            if ($PSCmdlet.ShouldProcess($target, 'Destroy file system')) {
                $disableBody = @{
                    nfs  = @{ v3_enabled = $false; v4_1_enabled = $false }
                    smb  = @{ enabled = $false }
                    http = @{ enabled = $false }
                }
                try {
                    Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-systems' -Body $disableBody -QueryParams $queryParams | Out-Null
                } catch { }
                $body = @{ destroyed = $true }
                Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-systems' -Body $body -QueryParams $queryParams
            }
        }
        else {
            # Hard delete: DELETE
            if ($PSCmdlet.ShouldProcess($target, 'Eradicate file system (PERMANENT)')) {
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'file-systems' -QueryParams $queryParams
            }
        }
    }
}
