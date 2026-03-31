function Get-PfbLegalHoldEntity {
    <#
    .SYNOPSIS
        Retrieves held entities associated with legal holds on the FlashBlade.
    .DESCRIPTION
        The Get-PfbLegalHoldEntity cmdlet returns the entities (file systems, buckets, etc.)
        that are subject to one or more legal holds on the connected Pure Storage FlashBlade.
        Use the cross-reference parameters to filter by hold or member.
    .PARAMETER HoldName
        One or more legal hold names to filter entities by.
    .PARAMETER HoldId
        One or more legal hold IDs to filter entities by.
    .PARAMETER MemberName
        One or more member names to filter by.
    .PARAMETER MemberId
        One or more member IDs to filter by.
    .PARAMETER Filter
        A server-side filter expression to narrow results.
    .PARAMETER Sort
        Sort field and direction (e.g., "member.name" or "member.name-").
    .PARAMETER Limit
        Maximum number of items to return.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Get-PfbLegalHoldEntity -HoldName "litigation-hold-2024"

        Retrieves all entities under the legal hold named "litigation-hold-2024".
    .EXAMPLE
        Get-PfbLegalHoldEntity -MemberName "fs1"

        Retrieves all legal hold associations for the member "fs1".
    .EXAMPLE
        Get-PfbLegalHoldEntity -HoldName "litigation-hold-2024" -MemberName "fs1" -Limit 10

        Retrieves up to 10 held-entity records for the specified hold and member.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$HoldName,

        [Parameter()]
        [string[]]$HoldId,

        [Parameter()]
        [string[]]$MemberName,

        [Parameter()]
        [string[]]$MemberId,

        [Parameter()] [string]$Filter,
        [Parameter()] [string]$Sort,
        [Parameter()] [int]$Limit,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($HoldName)   { $queryParams['hold_names']   = $HoldName -join ',' }
    if ($HoldId)     { $queryParams['hold_ids']     = $HoldId -join ',' }
    if ($MemberName) { $queryParams['member_names'] = $MemberName -join ',' }
    if ($MemberId)   { $queryParams['member_ids']   = $MemberId -join ',' }
    if ($Filter)     { $queryParams['filter']       = $Filter }
    if ($Sort)       { $queryParams['sort']         = $Sort }
    if ($Limit -gt 0) { $queryParams['limit']       = $Limit }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'legal-holds/held-entities' -QueryParams $queryParams -AutoPaginate
}
