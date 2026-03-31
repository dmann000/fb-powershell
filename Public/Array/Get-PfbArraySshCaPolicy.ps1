function Get-PfbArraySshCaPolicy {
    <#
    .SYNOPSIS
        Retrieves SSH CA policies associated with arrays from a FlashBlade.
    .DESCRIPTION
        The Get-PfbArraySshCaPolicy cmdlet returns the cross-reference between arrays and
        SSH certificate authority policies on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more array member names to filter by.
    .PARAMETER MemberId
        One or more array member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbArraySshCaPolicy

        Retrieves all array SSH CA policy associations.
    .EXAMPLE
        Get-PfbArraySshCaPolicy -PolicyName "ssh-ca-prod"

        Retrieves array associations for the specified SSH CA policy.
    .EXAMPLE
        Get-PfbArraySshCaPolicy -MemberName "array1" -Limit 5

        Retrieves up to 5 SSH CA policy associations for the specified array.
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [string[]]$PolicyName,
        [Parameter()] [string[]]$PolicyId,
        [Parameter()] [string[]]$MemberName,
        [Parameter()] [string[]]$MemberId,
        [Parameter()] [string]$Filter, [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName -join ',' }
    if ($PolicyId) { $queryParams['policy_ids'] = $PolicyId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId) { $queryParams['member_ids'] = $MemberId -join ',' }
    if ($Filter) { $queryParams['filter'] = $Filter }
    if ($Limit -gt 0) { $queryParams['limit'] = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/ssh-certificate-authority-policies' -QueryParams $queryParams -AutoPaginate
}
