function Update-PfbBucketAuditFilter {
    <#
    .SYNOPSIS
        Updates an existing bucket audit filter on the FlashBlade.
    .DESCRIPTION
        Modifies an existing audit filter for a bucket identified by member name
        or member ID. Use the Attributes parameter to supply the properties to
        update as a hashtable.
    .PARAMETER MemberName
        The name of the bucket whose audit filter should be updated.
    .PARAMETER MemberId
        The ID of the bucket whose audit filter should be updated.
    .PARAMETER Attributes
        A hashtable of audit filter properties to update.
        Only specified properties are changed.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbBucketAuditFilter -MemberName "mybucket" -Attributes @{ actions = @("s3.GetObject","s3.PutObject") }

        Updates the audit filter for 'mybucket' to log GetObject and PutObject operations.
    .EXAMPLE
        Update-PfbBucketAuditFilter -MemberId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Attributes @{ actions = @("s3.DeleteObject") }

        Updates the audit filter by bucket ID.
    .EXAMPLE
        Update-PfbBucketAuditFilter -MemberName "mybucket" -Attributes @{ enabled = $true }

        Enables the audit filter for the specified bucket.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByMemberName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberId', Mandatory)]
        [string]$MemberId,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($MemberName) { $queryParams['member_names'] = $MemberName }
        if ($MemberId)   { $queryParams['member_ids']   = $MemberId }

        $target = if ($MemberName) { $MemberName } else { $MemberId }

        if ($PSCmdlet.ShouldProcess($target, 'Update bucket audit filter')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'buckets/audit-filters' -Body $Attributes -QueryParams $queryParams
        }
    }
}
