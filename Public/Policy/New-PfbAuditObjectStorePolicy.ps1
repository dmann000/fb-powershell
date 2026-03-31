function New-PfbAuditObjectStorePolicy {
    <#
    .SYNOPSIS
        Creates a new audit object-store policy on the FlashBlade.
    .DESCRIPTION
        The New-PfbAuditObjectStorePolicy cmdlet creates an audit object-store policy on the
        connected Pure Storage FlashBlade. Use the Attributes parameter to supply a hashtable
        of policy properties, or provide individual parameters.
    .PARAMETER Name
        The name of the audit object-store policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbAuditObjectStorePolicy -Name "audit-obj-pol1"

        Creates a new audit object-store policy named "audit-obj-pol1".
    .EXAMPLE
        New-PfbAuditObjectStorePolicy -Name "audit-obj-pol1" -Attributes @{ enabled = $true }

        Creates a new audit object-store policy with custom attributes.
    .EXAMPLE
        New-PfbAuditObjectStorePolicy -Name "audit-obj-pol1" -Enabled

        Creates an enabled audit object-store policy.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create audit object-store policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'audit-object-store-policies' -Body $body -QueryParams $queryParams
    }
}
