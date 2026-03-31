function Set-PfbCredential {
    <#
    .SYNOPSIS
        Caches a PSCredential for FlashBlade authentication.
    .DESCRIPTION
        Stores a PSCredential object in the module session for use with Connect-PfbArray.
        This allows you to set credentials once and reuse them across multiple connections
        without re-entering them. Matches the FlashArray Set-Pfa2Credential pattern.
    .PARAMETER Credential
        The PSCredential object to cache. Use Get-Credential to create one interactively.
    .EXAMPLE
        Set-PfbCredential -Credential (Get-Credential)

        Prompts for credentials and caches them for later use.
    .EXAMPLE
        $cred = New-Object PSCredential("DOMAIN\admin", (ConvertTo-SecureString "pass" -AsPlainText -Force))
        Set-PfbCredential -Credential $cred

        Caches AD credentials non-interactively for scripting.
    .EXAMPLE
        Set-PfbCredential -Credential (Get-Credential)
        Connect-PfbArray -Endpoint 10.0.0.1 -Credential (Get-PfbCredential) -IgnoreCertificateError

        Cache credentials once, then use them to connect.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Management.Automation.PSCredential]$Credential
    )

    $script:PfbCachedCredential = $Credential
    Write-Verbose "Credential cached for user '$($Credential.UserName)'."
}
