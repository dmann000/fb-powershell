function Get-PfbCredential {
    <#
    .SYNOPSIS
        Retrieves the cached PSCredential for FlashBlade authentication.
    .DESCRIPTION
        Returns the PSCredential object previously stored with Set-PfbCredential.
        If no credential has been cached, prompts the user interactively via Get-Credential.
        Matches the FlashArray Get-Pfa2Credential pattern.
    .EXAMPLE
        $cred = Get-PfbCredential

        Returns the cached credential, or prompts if none cached.
    .EXAMPLE
        Set-PfbCredential -Credential (Get-Credential)
        Connect-PfbArray -Endpoint 10.0.0.1 -Credential (Get-PfbCredential) -IgnoreCertificateError

        Cache and retrieve credentials for connecting.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCredential])]
    param()

    if ($script:PfbCachedCredential) {
        return $script:PfbCachedCredential
    }
    else {
        Write-Warning "No cached credential found. Prompting for credentials."
        $cred = Get-Credential -Message "Enter FlashBlade credentials"
        $script:PfbCachedCredential = $cred
        return $cred
    }
}
