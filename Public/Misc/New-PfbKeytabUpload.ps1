function New-PfbKeytabUpload {
    <#
    .SYNOPSIS
        Uploads a keytab file to a FlashBlade array.
    .DESCRIPTION
        The New-PfbKeytabUpload cmdlet uploads a keytab file to the connected Pure Storage
        FlashBlade. Keytabs are used for Kerberos authentication with Active Directory.
    .PARAMETER Attributes
        A hashtable of keytab upload attributes, including the keytab file content.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbKeytabUpload -Attributes @{ keytab_file = [System.IO.File]::ReadAllBytes("krb5.keytab") }

        Uploads a keytab file from disk.
    .EXAMPLE
        New-PfbKeytabUpload -Attributes @{ name_prefix = "ad-keytab" } -WhatIf

        Shows what would happen without actually uploading the keytab.
    .EXAMPLE
        $bytes = [System.IO.File]::ReadAllBytes("C:\temp\krb5.keytab"); New-PfbKeytabUpload -Attributes @{ keytab_file = $bytes }

        Reads a keytab file and uploads it to the FlashBlade.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )
    Assert-PfbConnection -Array ([ref]$Array)
    if ($PSCmdlet.ShouldProcess('FlashBlade', 'Upload keytab')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'keytabs/upload' -Body $Attributes
    }
}
