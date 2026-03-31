function New-PfbBucket {
    <#
    .SYNOPSIS
        Creates a new S3 bucket on the FlashBlade.
    .PARAMETER Name
        The name of the bucket to create.
    .PARAMETER Account
        The object store account name to associate with the bucket.
    .PARAMETER Versioning
        Enable versioning on the bucket ('enabled', 'suspended', or 'none').
    .PARAMETER QuotaLimit
        Quota limit in bytes for the bucket.
    .PARAMETER Attributes
        A hashtable of additional attributes.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        New-PfbBucket -Name "mybucket" -Account "myaccount"
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [string]$Account,

        [Parameter()]
        [ValidateSet('enabled', 'suspended', 'none')]
        [string]$Versioning,

        [Parameter()]
        [int64]$QuotaLimit,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($Account)           { $body['account'] = @{ name = $Account } }
        if ($Versioning)        { $body['versioning'] = $Versioning }
        if ($QuotaLimit -gt 0)  { $body['quota_limit'] = $QuotaLimit }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create bucket')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'buckets' -Body $body -QueryParams $queryParams
    }
}
