function Remove-PfbRealm {
    <#
    .SYNOPSIS
        Removes (destroys or eradicates) a realm from the FlashBlade.
    .DESCRIPTION
        Destroys a realm (soft delete) or eradicates a previously destroyed realm
        (permanent delete). Destroyed realms can be recovered within 24 hours using
        Update-PfbRealm -Name "realm1" -Destroyed $false.
    .PARAMETER Name
        The name of the realm to remove.
    .PARAMETER Id
        The ID of the realm to remove.
    .PARAMETER Eradicate
        Permanently eradicate a destroyed realm. Cannot be undone.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Remove-PfbRealm -Name "realm1"
    .EXAMPLE
        Remove-PfbRealm -Name "realm1" -Eradicate
    .EXAMPLE
        Remove-PfbRealm -Id "12345678-1234-1234-1234-123456789abc" -Eradicate
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
            if ($PSCmdlet.ShouldProcess($target, 'Destroy realm')) {
                $body = @{ destroyed = $true }
                Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'realms' -Body $body -QueryParams $queryParams
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($target, 'Eradicate realm (PERMANENT)')) {
                Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'realms' -QueryParams $queryParams
            }
        }
    }
}
