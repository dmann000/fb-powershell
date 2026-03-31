function Remove-PfbS3ExportRule {
    <#
    .SYNOPSIS
        Removes an S3 export policy rule from the FlashBlade.
    .DESCRIPTION
        Deletes a rule from an S3 export policy identified by rule name or by
        policy name/ID. This action is irreversible. Use -Confirm:$false to
        suppress the confirmation prompt in automation scenarios.
    .PARAMETER Name
        The name of the S3 export rule to remove (e.g. 's3-export-01.1').
    .PARAMETER PolicyName
        The name of the S3 export policy whose rule should be removed.
    .PARAMETER PolicyId
        The ID of the S3 export policy whose rule should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbS3ExportRule -Name "s3-export-01.1"

        Removes the S3 export rule by name.
    .EXAMPLE
        Remove-PfbS3ExportRule -Name "s3-export-01.1" -Confirm:$false

        Removes the S3 export rule without confirmation.
    .EXAMPLE
        Remove-PfbS3ExportRule -PolicyName "s3-export-01" -Name "s3-export-01.1"

        Removes a specific rule from the named policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter()]
        [string]$PolicyName,

        [Parameter()]
        [string]$PolicyId,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{ 'names' = $Name }
        if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
        if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }

        if ($PSCmdlet.ShouldProcess($Name, 'Remove S3 export rule')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 's3-export-policies/rules' -QueryParams $queryParams
        }
    }
}
