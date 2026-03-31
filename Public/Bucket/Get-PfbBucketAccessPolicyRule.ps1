function Get-PfbBucketAccessPolicyRule {
    <#
    .SYNOPSIS
        Retrieves bucket access policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for bucket access policies. Rules define the specific
        permissions within a bucket access policy such as allowed actions,
        principals, and resources. Filter by fully-qualified name, bucket
        member name, or policy name.

        NOTE: The FlashBlade API requires at least one of -Name, -Id,
        -MemberName, or -PolicyName to be specified.
    .PARAMETER Name
        One or more fully-qualified bucket access policy rule names.
    .PARAMETER Id
        One or more bucket access policy rule IDs.
    .PARAMETER MemberName
        One or more bucket names to retrieve access policy rules for.
    .PARAMETER PolicyName
        One or more access policy names to retrieve rules for.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g. 'name' or 'name-').
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbBucketAccessPolicyRule -MemberName "mybucket"

        Returns all bucket access policy rules for the specified bucket.
    .EXAMPLE
        Get-PfbBucketAccessPolicyRule -PolicyName "read-only-policy"

        Returns rules for the policy named 'read-only-policy'.
    .EXAMPLE
        Get-PfbBucketAccessPolicyRule -MemberName "mybucket" -PolicyName "read-only-policy"

        Returns rules for a specific policy on a specific bucket.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByMemberName')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'ByMemberName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$MemberName,

        [Parameter()]
        [string[]]$PolicyName,

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
    }

    process {
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($Id)         { foreach ($i in $Id)         { $allIds.Add($i) } }
        if ($MemberName) { foreach ($n in $MemberName) { $allMemberNames.Add($n) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0)       { $queryParams['names']        = $allNames -join ',' }
        if ($allIds.Count -gt 0)         { $queryParams['ids']          = $allIds -join ',' }
        if ($allMemberNames.Count -gt 0) { $queryParams['member_names'] = $allMemberNames -join ',' }
        if ($PolicyName)                  { $queryParams['policy_names'] = $PolicyName -join ',' }
        if ($Filter)                      { $queryParams['filter']       = $Filter }
        if ($Sort)                        { $queryParams['sort']         = $Sort }
        if ($Limit -gt 0)               { $queryParams['limit']        = $Limit }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/bucket-access-policies/rules' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Either names or ids' -or $_ -match 'Policy must be specified') {
                Write-Warning "Bucket access policy rules require the -Name parameter with a fully-qualified name, or the -Id parameter."
                return
            }
            throw
        }
    }
}
