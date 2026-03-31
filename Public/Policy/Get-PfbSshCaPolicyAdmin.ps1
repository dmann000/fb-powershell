function Get-PfbSshCaPolicyAdmin {
    <#
    .SYNOPSIS
        Retrieves SSH CA policy admin associations from a FlashBlade array.
    .DESCRIPTION
        The Get-PfbSshCaPolicyAdmin cmdlet returns the cross-reference between SSH certificate
        authority policies and admin users on the connected Pure Storage FlashBlade.
    .PARAMETER PolicyName
        One or more policy names to filter by.
    .PARAMETER PolicyId
        One or more policy IDs to filter by.
    .PARAMETER MemberName
        One or more admin member names to filter by.
    .PARAMETER MemberId
        One or more admin member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Limit
        Maximum number of entries to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbSshCaPolicyAdmin

        Retrieves all SSH CA policy admin associations.
    .EXAMPLE
        Get-PfbSshCaPolicyAdmin -PolicyName "ssh-ca-prod"

        Retrieves admin associations for the specified SSH CA policy.
    .EXAMPLE
        Get-PfbSshCaPolicyAdmin -MemberName "pureuser"

        Retrieves SSH CA policy associations for the specified admin.
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

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'ssh-certificate-authority-policies/admins' -QueryParams $queryParams -AutoPaginate
}
