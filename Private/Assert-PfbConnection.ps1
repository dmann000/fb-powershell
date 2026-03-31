function Assert-PfbConnection {
    <#
    .SYNOPSIS
        Validates that an active FlashBlade connection exists.
    .DESCRIPTION
        Called at the beginning of every public cmdlet. If -Array is not explicitly provided,
        resolves to the default (last connected) array. Throws if no connection is available.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ref]$Array
    )

    if ($null -ne $Array -and $null -ne $Array.Value) {
        # Explicit array provided - validate it has auth
        if ([string]::IsNullOrEmpty($Array.Value.AuthToken)) {
            throw "The provided FlashBlade connection is not authenticated. Run Connect-PfbArray first."
        }
        return
    }

    # No explicit array - use default
    if ($null -eq $script:PfbDefaultArray) {
        throw "Not connected to a FlashBlade array. Run Connect-PfbArray first."
    }

    if ($null -ne $Array) {
        $Array.Value = $script:PfbDefaultArray
    }
}
