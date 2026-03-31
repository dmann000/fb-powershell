function New-PfbNfsExportPolicy {
    <#
    .SYNOPSIS
        Creates a new NFS export policy on the FlashBlade.
    .DESCRIPTION
        Creates a new NFS export policy with the specified name and optional settings.
        Use the Attributes parameter to supply a complete body hashtable, or use
        individual parameters to build the request.
    .PARAMETER Name
        The name of the NFS export policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
        When specified, this is used as the entire request body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNfsExportPolicy -Name "nfs-export-01"

        Creates a new NFS export policy named 'nfs-export-01'.
    .EXAMPLE
        New-PfbNfsExportPolicy -Name "nfs-export-01" -Enabled

        Creates a new enabled NFS export policy.
    .EXAMPLE
        New-PfbNfsExportPolicy -Name "nfs-export-01" -Attributes @{ enabled = $true; rules = @(@{ client = "*"; access = "root-squash" }) }

        Creates a new NFS export policy with custom attributes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [switch]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($Attributes) { $body = $Attributes }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create NFS export policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'nfs-export-policies' -Body $body -QueryParams $queryParams
    }
}
