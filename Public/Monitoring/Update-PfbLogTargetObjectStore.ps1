function Update-PfbLogTargetObjectStore {
    <#
    .SYNOPSIS
        Updates a log-target object-store configuration on the FlashBlade.
    .DESCRIPTION
        The Update-PfbLogTargetObjectStore cmdlet modifies a log-target object-store
        configuration on the connected Pure Storage FlashBlade. Identify the target by
        name or ID and supply the changed properties via Attributes.
    .PARAMETER Name
        The name of the log-target object store to update.
    .PARAMETER Id
        The ID of the log-target object store to update.
    .PARAMETER Attributes
        A hashtable of attributes to update on the configuration.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbLogTargetObjectStore -Name "log-obj-target1" -Attributes @{ prefix = '/new-prefix' }

        Updates the prefix on the log-target object-store configuration.
    .EXAMPLE
        Update-PfbLogTargetObjectStore -Id "12345" -Attributes @{ enabled = $true }

        Enables the log-target object store identified by ID.
    .EXAMPLE
        Update-PfbLogTargetObjectStore -Name "log-obj-target1" -Attributes @{ bucket = 'new-bucket' }

        Updates the bucket reference on the log-target object store.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
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

        if ($PSCmdlet.ShouldProcess($target, 'Update log-target object store')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'log-targets/object-store' -Body $body -QueryParams $queryParams
        }
    }
}
