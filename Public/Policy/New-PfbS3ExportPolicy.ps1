function New-PfbS3ExportPolicy {
    <#
    .SYNOPSIS
        Creates a new S3 export policy on the FlashBlade.
    .DESCRIPTION
        Creates a new S3 export policy with the specified name and optional settings.
        Use the Attributes parameter to supply a complete body hashtable, or use
        individual parameters to build the request.
    .PARAMETER Name
        The name of the S3 export policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbS3ExportPolicy -Name "s3-export-01"

        Creates a new S3 export policy named 's3-export-01'.
    .EXAMPLE
        New-PfbS3ExportPolicy -Name "s3-export-01" -Enabled

        Creates a new enabled S3 export policy.
    .EXAMPLE
        New-PfbS3ExportPolicy -Name "s3-export-01" -Attributes @{ enabled = $true }

        Creates a new S3 export policy with custom attributes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create S3 export policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 's3-export-policies' -Body $body -QueryParams $queryParams
    }
}
