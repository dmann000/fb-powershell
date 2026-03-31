function New-PfbFileSystemExport {
    <#
    .SYNOPSIS
        Creates a new file system export on the FlashBlade.
    .DESCRIPTION
        Creates a file system export rule with the specified name and configuration.
        Use the Attributes parameter to pass a hashtable of export properties.
    .PARAMETER Name
        The name of the file system export to create.
    .PARAMETER Attributes
        A hashtable of export attributes (e.g., rules, protocols, permissions).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        New-PfbFileSystemExport -Name "export1" -Attributes @{ rules = "*(rw,no_root_squash)" }
        Creates a new export with the specified NFS rules.
    .EXAMPLE
        New-PfbFileSystemExport -Name "export1" -Attributes @{ enabled = $true; rules = "10.0.0.0/8(rw)" }
        Creates a new export with a network-restricted rule.
    .EXAMPLE
        $attrs = @{ rules = "*(ro)"; user_mapping_enabled = $true }
        New-PfbFileSystemExport -Name "export1" -Attributes $attrs
        Creates a new export using a pre-built attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create file system export')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-system-exports' -Body $body -QueryParams $queryParams
    }
}
