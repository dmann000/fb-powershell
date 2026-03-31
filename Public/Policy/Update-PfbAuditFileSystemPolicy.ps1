function Update-PfbAuditFileSystemPolicy {
    <#
    .SYNOPSIS
        Updates an existing audit file-system policy on the FlashBlade.
    .DESCRIPTION
        The Update-PfbAuditFileSystemPolicy cmdlet modifies an audit file-system policy on the
        connected Pure Storage FlashBlade. Identify the policy by name or ID and supply the
        changed properties via Attributes or individual parameters.
    .PARAMETER Name
        The name of the audit file-system policy to update.
    .PARAMETER Id
        The ID of the audit file-system policy to update.
    .PARAMETER Enabled
        Enable or disable the policy.
    .PARAMETER Attributes
        A hashtable of attributes to update on the policy.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbAuditFileSystemPolicy -Name "audit-fs-pol1" -Enabled:$false

        Disables the audit file-system policy named "audit-fs-pol1".
    .EXAMPLE
        Update-PfbAuditFileSystemPolicy -Id "12345" -Attributes @{ enabled = $true }

        Enables the audit file-system policy identified by ID.
    .EXAMPLE
        Update-PfbAuditFileSystemPolicy -Name "audit-fs-pol1" -Attributes @{ operations = @('read','write') }

        Updates the operations list on the specified audit file-system policy.
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

        if ($PSCmdlet.ShouldProcess($target, 'Update audit file-system policy')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'audit-file-systems-policies' -Body $body -QueryParams $queryParams
        }
    }
}
