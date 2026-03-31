function Set-PfbCertificatePolicy {
    <#
    .SYNOPSIS
        Configures SSL certificate validation bypass for FlashBlade connections.
    .DESCRIPTION
        Handles the divergence between PowerShell 5.1 and 7+ for ignoring SSL certificate errors.
        On PS 5.1, uses ServicePointManager callback. On PS 7+, sets a flag for -SkipCertificateCheck.
    #>
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        # PowerShell 5.1: Use .NET ServicePointManager
        if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
            Add-Type -TypeDefinition @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
        }
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    }
    # PowerShell 7+: handled via -SkipCertificateCheck on Invoke-RestMethod
}
