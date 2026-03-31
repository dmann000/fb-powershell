function Remove-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Removes a bucket audit filter from the FlashBlade.
    .DESCRIPTION
        Deletes an audit filter from a bucket identified by member name or member ID.
        This action is irreversible. Use -Confirm:$false to suppress the confirmation
        prompt in automation scenarios.
    .PARAMETER MemberName
        The name of the bucket whose audit filter should be removed.
    .PARAMETER MemberId
        The ID of the bucket whose audit filter should be removed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Remove-PfbBucketAuditFilter -MemberName "mybucket"

        Removes the audit filter for the bucket named 'mybucket'.
    .EXAMPLE
        Remove-PfbBucketAuditFilter -MemberId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

        Removes the audit filter by bucket ID.
    .EXAMPLE
        Remove-PfbBucketAuditFilter -MemberName "mybucket" -Confirm:$false

        Removes the audit filter without confirmation.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(ParameterSetName = 'ByMemberName', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberId', Mandatory)]
        [string]$MemberId,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $target = if ($MemberName) { $MemberName } else { $MemberId }
        $queryParams = @{}
        if ($MemberName) { $queryParams['member_names'] = $MemberName }
        if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

        if ($PSCmdlet.ShouldProcess($target, 'Remove bucket audit filter')) {
            Invoke-PfbApiRequest -Array $Array -Method DELETE -Endpoint 'buckets/audit-filters' -QueryParams $queryParams
        }
    }
}
