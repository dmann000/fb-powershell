function Get-PfbBucketAccessPolicy {
    <#
    .SYNOPSIS
        Retrieves bucket access policies from the FlashBlade.
    .DESCRIPTION
        Returns one or more bucket access policies from the FlashBlade array.
        Bucket access policies define S3 bucket-level access controls. Filter
        results by fully-qualified name (bucket/account:policy), or by bucket
        member name/ID and policy name/ID separately.

        NOTE: The FlashBlade API requires at least one of -Name, -Id,
        -MemberName, or -PolicyName to be specified.
    .PARAMETER Name
        One or more fully-qualified bucket access policy names
        (e.g. 'mybucket/myaccount:mypolicy').
    .PARAMETER Id
        One or more bucket access policy IDs.
    .PARAMETER MemberName
        One or more bucket names to retrieve access policies for.
    .PARAMETER MemberId
        One or more bucket IDs to retrieve access policies for.
    .PARAMETER PolicyName
        One or more access policy names to retrieve.
    .PARAMETER PolicyId
        One or more access policy IDs to retrieve.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketAccessPolicy -MemberName "mybucket"

        Returns access policies for the bucket named 'mybucket'.
    .EXAMPLE
        Get-PfbBucketAccessPolicy -Name "mybucket/myaccount:mypolicy"

        Returns the specific bucket access policy by fully-qualified name.
    .EXAMPLE
        Get-PfbBucketAccessPolicy -PolicyName "read-only-policy" -MemberName "mybucket"

        Returns a specific access policy for a specific bucket.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByMemberName')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'ByMemberName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$MemberName,

        [Parameter(ParameterSetName = 'ByMemberId')]
        [string[]]$MemberId,

        [Parameter()]
        [string[]]$PolicyName,

        [Parameter()]
        [string[]]$PolicyId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds = [System.Collections.Generic.List[string]]::new()
        $allMemberNames = [System.Collections.Generic.List[string]]::new()
        $allMemberIds = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($Id)         { foreach ($i in $Id)         { $allIds.Add($i) } }
        if ($MemberName) { foreach ($n in $MemberName) { $allMemberNames.Add($n) } }
        if ($MemberId)   { foreach ($i in $MemberId)   { $allMemberIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0)       { $queryParams['names']        = $allNames -join ',' }
        if ($allIds.Count -gt 0)         { $queryParams['ids']          = $allIds -join ',' }
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($allMemberIds.Count -gt 0)   { $queryParams['member_ids']   = $allMemberIds -join ',' }
        if ($PolicyName)                  { $queryParams['policy_names'] = $PolicyName -join ',' }
        if ($PolicyId)                    { $queryParams['policy_ids']   = $PolicyId -join ',' }
        if ($Filter)                      { $queryParams['filter']       = $Filter }
        if ($Sort)                        { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)               { $queryParams['limit']        = $Limit }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/bucket-access-policies' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Either names or ids' -or $_ -match 'Policy must be specified') {
                Write-Warning "Bucket access policies require the -Name parameter with a fully-qualified 'bucket/policy' name, or the -Id parameter. Use Get-PfbObjectStoreAccessPolicy to list available policies."
                return
            }
            throw
        }
    }
}
