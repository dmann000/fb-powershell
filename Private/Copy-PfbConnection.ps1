# Copy-on-write for the connection object. Set-/Clear-PfbContext return a NEW connection and
# never mutate the caller's: context is a TARGETING mutation, unlike the transparent
# AuthToken/TokenExpiresAt writes the auto-reconnect path makes in place. See spec section 2.

function Copy-PfbConnection {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param([Parameter(Mandatory)][PSCustomObject]$Array)

    # .PSObject.Copy() is a shallow clone that PRESERVES PSTypeNames. Rebuilding from a
    # [PSCustomObject]@{} literal would drop 'PureStorage.FlashBlade.Connection'.
    # Deliberately does NOT touch $script:PfbArrays/$script:PfbDefaultArray -- repointing the
    # caches is Update-PfbConnectionCache's single responsibility.
    $Array.PSObject.Copy()
}

function Update-PfbConnectionCache {
    [CmdletBinding()]
    param([Parameter(Mandatory)][PSCustomObject]$Array)

    # Both pointers must move or callers using the implicit default connection keep hitting
    # the OLD object after the cmdlet "succeeded". Same idiom as the OAuth2 refresh path.
    if ($script:PfbDefaultArray -and $script:PfbDefaultArray.Endpoint -eq $Array.Endpoint) {
        $script:PfbDefaultArray = $Array
    }
    if ($script:PfbArrays -and $script:PfbArrays.ContainsKey($Array.Endpoint)) {
        $script:PfbArrays[$Array.Endpoint] = $Array
    }
}
