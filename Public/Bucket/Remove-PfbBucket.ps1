function Remove-PfbBucket {
    <#
    .SYNOPSIS
        Removes a bucket from the FlashBlade.
    .PARAMETER Name
        The name of the bucket to remove.
    .PARAMETER Id
        The ID of the bucket to remove.
    .PARAMETER Eradicate
        Permanently eradicate a destroyed bucket.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Remove-PfbBucket -Name "mybucket"
    .EXAMPLE
        Remove-PfbBucket -Name "mybucket" -Eradicate
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
            if ($PSCmdlet.ShouldProcess($target, 'Destroy bucket')) {
                $body = @{ destroyed = $true }
                Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'buckets' -Body $body -QueryParams $queryParams
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($target, 'Eradicate bucket (PERMANENT)')) {
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets' -QueryParams $queryParams
            }
        }
    }
}
