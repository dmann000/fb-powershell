function Get-PfbArraySpace {
    <#
    .SYNOPSIS
        Retrieves FlashBlade array space utilization.
    .DESCRIPTION
        Returns storage space metrics including capacity, data reduction, and usage.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .PARAMETER Type
        Filter by space type. Valid values: 'array', 'file-system', 'object-store'.
        Defaults to 'array' if not specified.
    .EXAMPLE
        Get-PfbArraySpace
    .NOTES
        <!-- PfbContext: generated from Data/PfbCapabilityMap.json contextScope. Do not edit. -->
        Context requirement (GET /arrays/space): the context scope for this endpoint is not
        recorded in the capability map, so the module will not pre-validate a context
        for it. A fleet or array context may still be required by the array itself; if
        a call fails with a context error, set one with Set-PfbContext or scope the
        call with Invoke-PfbInContext.
        <!-- /PfbContext -->
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [PSCustomObject]$Array,

        [Parameter()]
        [ValidateSet('array', 'file-system', 'object-store')]
        [string]$Type
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($Type) { $queryParams['type'] = $Type }

    Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'arrays/space' -QueryParams $queryParams -AutoPaginate
}
