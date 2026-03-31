function New-PfbLogTargetObjectStore {
    <#
    .SYNOPSIS
        Creates a new log-target object-store configuration on the FlashBlade.
    .DESCRIPTION
        The New-PfbLogTargetObjectStore cmdlet creates a log-target object-store configuration
        on the connected Pure Storage FlashBlade. Use the Attributes parameter to supply a
        hashtable of configuration properties, or provide individual parameters.
    .PARAMETER Name
        The name of the log-target object store to create.
    .PARAMETER Attributes
        A hashtable of additional attributes for the configuration body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbLogTargetObjectStore -Name "log-obj-target1"

        Creates a new log-target object-store configuration named "log-obj-target1".
    .EXAMPLE
        New-PfbLogTargetObjectStore -Name "log-obj-target1" -Attributes @{ bucket = 'audit-bucket' }

        Creates a log-target object-store configuration with a bucket reference.
    .EXAMPLE
        New-PfbLogTargetObjectStore -Name "log-obj-target1" -Attributes @{ prefix = 'logs/' }

        Creates a log-target object store with a specific prefix path.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create log-target object store')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'log-targets/object-store' -Body $body -QueryParams $queryParams
    }
}
