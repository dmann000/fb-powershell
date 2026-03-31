function Update-PfbAuditObjectStorePolicy {
    <#
    .SYNOPSIS
        Updates an existing audit object-store policy on the FlashBlade.
    .DESCRIPTION
        The Update-PfbAuditObjectStorePolicy cmdlet modifies an audit object-store policy on
        the connected Pure Storage FlashBlade. Identify the policy by name or ID and supply
        the changed properties via Attributes or individual parameters.
    .PARAMETER Name
        The name of the audit object-store policy to update.
    .PARAMETER Id
        The ID of the audit object-store policy to update.
    .PARAMETER Enabled
        Enable or disable the policy.
    .PARAMETER Attributes
        A hashtable of attributes to update on the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAuditObjectStorePolicy -Name "audit-obj-pol1" -Enabled:$false

        Disables the audit object-store policy named "audit-obj-pol1".
    .EXAMPLE
        Update-PfbAuditObjectStorePolicy -Id "12345" -Attributes @{ enabled = $true }

        Enables the audit object-store policy identified by ID.
    .EXAMPLE
        Update-PfbAuditObjectStorePolicy -Name "audit-obj-pol1" -Attributes @{ operations = @('s3.GetObject') }

        Updates the operations list on the specified audit object-store policy.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter()]
        [Nullable[bool]]$Enabled,

        [Parameter()]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        if ($Attributes) { $body = $Attributes }
        else {
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = [bool]$Enabled }
        }

        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }
        $target = if ($Name) { $Name } else { $Id }

        if ($PSCmdlet.ShouldProcess($target, 'Update audit object-store policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'audit-object-store-policies' -Body $body -QueryParams $queryParams
        }
    }
}
