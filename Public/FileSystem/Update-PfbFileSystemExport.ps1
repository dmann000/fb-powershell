function Update-PfbFileSystemExport {
    <#
    .SYNOPSIS
        Updates an existing file system export on the FlashBlade.
    .DESCRIPTION
        Modifies file system export attributes such as rules, enabled state, and
        other export properties. Identify the export by name or ID.
    .PARAMETER Name
        The name of the file system export to update.
    .PARAMETER Id
        The ID of the file system export to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the export.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, uses the default connection.
    .EXAMPLE
        Update-PfbFileSystemExport -Name "export1" -Attributes @{ rules = "*(ro)" }
        Updates the export rules to read-only.
    .EXAMPLE
        Update-PfbFileSystemExport -Id "abc-123" -Attributes @{ enabled = $false }
        Disables the specified export by ID.
    .EXAMPLE
        Update-PfbFileSystemExport -Name "export1" -Attributes @{ rules = "10.0.0.0/8(rw,no_root_squash)" }
        Updates the export with network-restricted rules.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()]
        [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $body = if ($Attributes) { $Attributes } else { @{} }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update file system export')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'file-system-exports' -Body $body -QueryParams $queryParams
        }
    }
}
