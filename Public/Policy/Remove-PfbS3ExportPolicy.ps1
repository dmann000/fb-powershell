function Remove-PfbS3ExportPolicy {
    <#
    .SYNOPSIS
        Removes an S3 export policy from the FlashBlade.
    .DESCRIPTION
        Deletes an S3 export policy identified by name or ID from the FlashBlade.
        This action is irreversible. Use -Confirm:$false to suppress the confirmation
        prompt in automation scenarios.
    .PARAMETER Name
        The name of the S3 export policy to remove.
    .PARAMETER Id
        The ID of the S3 export policy to remove.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbS3ExportPolicy -Name "s3-export-01"

        Removes the S3 export policy named 's3-export-01'.
    .EXAMPLE
        Remove-PfbS3ExportPolicy -Id "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the S3 export policy by ID.
    .EXAMPLE
        Remove-PfbS3ExportPolicy -Name "s3-export-01" -Confirm:$false

        Removes the S3 export policy without confirmation.
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

        if ($PSCmdlet.ShouldProcess($target, 'Remove S3 export policy')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 's3-export-policies' -QueryParams $queryParams
        }
    }
}
