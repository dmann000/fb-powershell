function Remove-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Removes a bucket audit filter from the FlashBlade.
    .DESCRIPTION
        Deletes an audit filter identified by audit filter name, bucket name, or
        bucket ID. This action is irreversible. Use -Confirm:$false to suppress
        the confirmation prompt in automation scenarios.
    .PARAMETER Name
        One or more audit filter names to remove.
    .PARAMETER BucketName
        One or more bucket names whose audit filters should be removed.
    .PARAMETER MemberId
        The ID of the bucket whose audit filter should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketAuditFilter -BucketName "mybucket"

        Removes the audit filter for the bucket named 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketAuditFilter -MemberId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the audit filter by bucket ID.
    .EXAMPLE
        Remove-PfbBucketAuditFilter -Name "myfilter" -Confirm:$false

        Removes the audit filter named 'myfilter' without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByBucketName', Mandatory, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

        [Parameter(ParameterSetName = 'ByMemberId', Mandatory)]
        [string]$MemberId,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name)       { $queryParams['names']        = $Name -join ',' }
        if ($BucketName) { $queryParams['bucket_names'] = $BucketName -join ',' }
        if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

        $target = if ($Name) { $Name -join ',' } elseif ($BucketName) { $BucketName -join ',' } else { $MemberId }

        if ($PSCmdlet.ShouldProcess($target, 'Remove bucket audit filter')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/audit-filters' -QueryParams $queryParams
        }
    }
}
