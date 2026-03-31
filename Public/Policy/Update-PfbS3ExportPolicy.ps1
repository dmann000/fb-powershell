function Update-PfbS3ExportPolicy {
    <#
    .SYNOPSIS
        Updates an existing S3 export policy on the FlashBlade.
    .DESCRIPTION
        Modifies an existing S3 export policy identified by name or ID.
        Supports enabling or disabling the policy and updating attributes.
        The Enabled parameter accepts $true or $false and can be used with
        the colon syntax (e.g. -Enabled:$false).
    .PARAMETER Name
        The name of the S3 export policy to update.
    .PARAMETER Id
        The ID of the S3 export policy to update.
    .PARAMETER Enabled
        Enable or disable the S3 export policy. Use -Enabled:$true or -Enabled:$false.
    .PARAMETER Attributes
        A hashtable of attributes to update. When specified, this is used as the
        entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbS3ExportPolicy -Name "s3-export-01" -Enabled:$false

        Disables the S3 export policy named 's3-export-01'.
    .EXAMPLE
        Update-PfbS3ExportPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Enabled:$true

        Enables the S3 export policy by ID.
    .EXAMPLE
        Update-PfbS3ExportPolicy -Name "s3-export-01" -Attributes @{ enabled = $true }

        Updates the S3 export policy using an attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update S3 export policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 's3-export-policies' -Body $body -QueryParams $queryParams
        }
    }
}
