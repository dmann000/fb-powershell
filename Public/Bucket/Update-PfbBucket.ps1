function Update-PfbBucket {
    <#
    .SYNOPSIS
        Updates an existing bucket on the FlashBlade.
    .PARAMETER Name
        The name of the bucket to update.
    .PARAMETER Id
        The ID of the bucket to update.
    .PARAMETER Versioning
        Set versioning state.
    .PARAMETER QuotaLimit
        Set quota limit in bytes.
    .PARAMETER Destroyed
        Set to $true to destroy or $false to recover.
    .PARAMETER Attributes
        A hashtable of attributes to update.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbBucket -Name "mybucket" -Versioning "enabled"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [ValidateSet('enabled', 'suspended', 'none')]
        [string]$Versioning,

        [Parameter()]
        [int64]$QuotaLimit,

        [Parameter()]
        [Nullable[bool]]$Destroyed,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) {
            $body = $Attributes
        }
        else {
            $body = @{}
            if ($Versioning)         { $body['versioning'] = $Versioning }
            if ($QuotaLimit -gt 0)   { $body['quota_limit'] = $QuotaLimit }
            if ($PSBoundParameters.ContainsKey('Destroyed')) { $body['destroyed'] = [bool]$Destroyed }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update bucket')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'buckets' -Body $body -QueryParams $queryParams
        }
    }
}
