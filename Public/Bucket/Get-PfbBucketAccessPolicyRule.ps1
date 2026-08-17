function Get-PfbBucketAccessPolicyRule {
    <#
    .SYNOPSIS
        Retrieves bucket access policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for bucket access policies. Rules define the specific
        permissions within a bucket access policy such as allowed actions,
        principals, and resources. Filter by fully-qualified name, bucket
        name, or policy name.

        NOTE: The FlashBlade API requires at least one of -Name, -Id,
        -BucketName, or -PolicyName to be specified.
    .PARAMETER Name
        One or more fully-qualified bucket access policy rule names.
    .PARAMETER Id
        One or more bucket access policy rule IDs.
    .PARAMETER BucketName
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
        Get-PfbBucketAccessPolicyRule -BucketName "mybucket"

        Returns all bucket access policy rules for the specified bucket.
    .EXAMPLE
        Get-PfbBucketAccessPolicyRule -PolicyName "read-only-policy"

        Returns rules for the policy named 'read-only-policy'.
    .EXAMPLE
        Get-PfbBucketAccessPolicyRule -BucketName "mybucket" -PolicyName "read-only-policy"

        Returns rules for a specific policy on a specific bucket.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByBucketName')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'ByBucketName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]$BucketName,

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
        $allBucketNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($Id)         { foreach ($i in $Id)         { $allIds.Add($i) } }
        if ($BucketName) { foreach ($b in $BucketName) { $allBucketNames.Add($b) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames -Ids $allIds
        if ($allBucketNames.Count -gt 0) { $queryParams['bucket_names'] = $allBucketNames -join ',' }
        if ($PolicyName)                 { $queryParams['policy_names'] = $PolicyName -join ',' }

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
