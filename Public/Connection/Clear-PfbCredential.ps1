function Clear-PfbCredential {
    <#
    .SYNOPSIS
        Clears the cached PSCredential for FlashBlade authentication.
    .DESCRIPTION
        Removes the PSCredential object previously stored with Set-PfbCredential.
        Use this when switching users or for security after completing operations.
        Matches the FlashArray Clear-Pfa2Credential pattern.
    .EXAMPLE
        Clear-PfbCredential

        Removes the cached credential from the session.
    .EXAMPLE
        Set-PfbCredential -Credential (Get-Credential)
        # ... do work ...
        Clear-PfbCredential

        Cache, use, and then clear credentials for security.
    #>
    [CmdletBinding()]
    param()

    $script:PfbCachedCredential = $null
    Write-Verbose "Cached credential cleared."
}
