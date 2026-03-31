function New-PfbKeytab {
    <#
    .SYNOPSIS
        Creates a new Kerberos keytab entry on the FlashBlade.
    .DESCRIPTION
        Uploads or creates a new Kerberos keytab entry on the FlashBlade for use with
        Active Directory or Kerberos-based authentication services.
    .PARAMETER Attributes
        A hashtable containing the keytab attributes such as the keytab file content
        and associated configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbKeytab -Attributes @{ source = "base64encodedcontent" }

        Creates a new keytab entry with the specified base64-encoded content.
    .EXAMPLE
        $keytab = @{ source = (Get-Content -Path "krb5.keytab" -Encoding Byte -Raw) }
        New-PfbKeytab -Attributes $keytab

        Creates a new keytab entry from a local keytab file.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('keytab', 'Create keytab')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'keytabs' -Body $Attributes
    }
}
