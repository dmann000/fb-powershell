function Clear-PfbContext {
    <#
    .SYNOPSIS
        Removes the durable Fusion context from a connection, returning a NEW connection.
    .DESCRIPTION
        Its own cmdlet rather than a -Clear switch, matching the Set-/Clear-PfbCredential
        precedent, and because @() must keep its distinct "run this one call locally" meaning
        at the Invoke-PfbInContext layer. Copy-on-write, like Set-PfbContext. No network call.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [PSCustomObject]$Array
    )

    $target = if ($Array) { $Array } else { $script:PfbDefaultArray }
    if (-not $target) {
        throw "Clear-PfbContext requires a connection: pass -Array, or connect first with Connect-PfbArray."
    }

    $copy = Copy-PfbConnection -Array $target
    $copy.DefaultContext = $null
    Update-PfbConnectionCache -Array $copy
    $copy
}
