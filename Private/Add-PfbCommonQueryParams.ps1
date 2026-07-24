function Add-PfbCommonQueryParams {
    <#
    .SYNOPSIS
        Adds common query parameters to a query-parameter hashtable.
    .DESCRIPTION
        Populates a hashtable with the standard -Filter, -Sort, -Limit, -TotalOnly,
        -Names, and -Ids query parameters used across all Get-Pfb* cmdlets. Uses
        ContainsKey semantics to detect bound parameters, allowing explicit passes
        of falsy values (e.g. -Limit 0 or empty-string -Filter) to be included.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Into,
        [Parameter(Mandatory)][System.Collections.IDictionary]$BoundParameters,
        [string[]]$Names,
        [string[]]$Ids
    )
    if ($BoundParameters.ContainsKey('Filter'))    { $Into['filter']     = $BoundParameters['Filter'] }
    if ($BoundParameters.ContainsKey('Sort'))      { $Into['sort']       = $BoundParameters['Sort'] }
    if ($BoundParameters.ContainsKey('Limit'))     { $Into['limit']      = $BoundParameters['Limit'] }
    if ($BoundParameters.ContainsKey('TotalOnly')) { $Into['total_only'] = 'true' }
    if ($Names) { $Into['names'] = $Names -join ',' }
    if ($Ids)   { $Into['ids']   = $Ids   -join ',' }
}
