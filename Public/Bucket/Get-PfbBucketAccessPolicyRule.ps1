function Get-PfbBucketAccessPolicyRule {
    <#
    .SYNOPSIS
        Retrieves bucket access policy rules from the FlashBlade.
    .DESCRIPTION
        Returns rules for bucket access policies. Rules define the specific
        permissions within a bucket access policy such as allowed actions,
        principals, and resources. Filter by fully-qualified name, bucket
        name, or policy name.

        GET /buckets/bucket-access-policies/rules declares no 'ids' selector,
        so there is no -Id parameter: the endpoint
        silently ignored the key and returned the unfiltered collection.
    .PARAMETER Name
        One or more fully-qualified bucket access policy rule names.
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

        # Within this family, the cross-endpoint chain from Get-PfbBucket into Get-PfbBucketAccessPolicyRule cannot
        # filter correctly: a producer's bare `name` bound to -BucketName / `bucket_names` is the defect
        # because `name` means different things by endpoint and metadata cannot identify its producer,
        # so no correct generic binding exists. An undeclared or non-matching query key returns HTTP 200
        # with the unfiltered collection; the guard's loud failure is therefore best. Do NOT remove it
        # or add an alias: that flips WrongScalar to Bound while sending the wrong name; revisit only if
        # the consumer can establish its producer, which parameter metadata alone cannot. Issue #90.
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
        $allBucketNames = [System.Collections.Generic.List[string]]::new()
    }

    process {
        Assert-PfbSelectorNotCoerced -Value $BucketName -OriginalInput $PSItem -ParameterName 'BucketName' -Hint (
            'Pipe the bucket name instead, e.g. Get-PfbBucket | Select-Object -ExpandProperty name | ' +
            'Get-PfbBucketAccessPolicyRule, or pass -BucketName explicitly.')
        if ($Name)       { foreach ($n in $Name)       { $allNames.Add($n) } }
        if ($BucketName) { foreach ($b in $BucketName) { $allBucketNames.Add($b) } }
    }

    end {
        $queryParams = @{}
        Add-PfbCommonQueryParams -Into $queryParams -BoundParameters $PSBoundParameters -Names $allNames
        if ($allBucketNames.Count -gt 0) { $queryParams['bucket_names'] = $allBucketNames -join ',' }
        if ($PolicyName)                 { $queryParams['policy_names'] = $PolicyName -join ',' }

        try {
            Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'buckets/bucket-access-policies/rules' -QueryParams $queryParams -AutoPaginate
        }
        catch {
            if ($_ -match 'Either names or ids' -or $_ -match 'Policy must be specified') {
                Write-Warning "Bucket access policy rules require the -Name parameter with a fully-qualified name, or -BucketName/-PolicyName."
                return
            }
            throw
        }
    }
}
