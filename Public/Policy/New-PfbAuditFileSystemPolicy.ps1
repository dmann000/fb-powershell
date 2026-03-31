function New-PfbAuditFileSystemPolicy {
    <#
    .SYNOPSIS
        Creates a new audit file-system policy on the FlashBlade.
    .DESCRIPTION
        The New-PfbAuditFileSystemPolicy cmdlet creates an audit file-system policy on the
        connected Pure Storage FlashBlade. Use the Attributes parameter to supply a hashtable
        of policy properties, or provide individual parameters.
    .PARAMETER Name
        The name of the audit file-system policy to create.
    .PARAMETER Enabled
        Whether the policy is enabled upon creation.
    .PARAMETER Attributes
        A hashtable of additional attributes for the policy body.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbAuditFileSystemPolicy -Name "audit-fs-pol1"

        Creates a new audit file-system policy named "audit-fs-pol1".
    .EXAMPLE
        New-PfbAuditFileSystemPolicy -Name "audit-fs-pol1" -Attributes @{ enabled = $true }

        Creates a new audit file-system policy with custom attributes.
    .EXAMPLE
        New-PfbAuditFileSystemPolicy -Name "audit-fs-pol1" -Enabled

        Creates an enabled audit file-system policy.
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

    if ($PSCmdlet.ShouldProcess($Name, 'Create audit file-system policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'audit-file-systems-policies' -Body $body -QueryParams $queryParams
    }
}
