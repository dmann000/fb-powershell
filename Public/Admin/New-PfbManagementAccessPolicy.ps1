function New-PfbManagementAccessPolicy {
    <#
    .SYNOPSIS
        Creates a new management access policy on the FlashBlade.
    .DESCRIPTION
        The New-PfbManagementAccessPolicy cmdlet creates a new management access policy on the
        connected Pure Storage FlashBlade. The policy name is required and attributes define the
        policy configuration. Supports ShouldProcess for confirmation prompts.
    .PARAMETER Name
        The name of the management access policy to create.
    .PARAMETER Attributes
        A hashtable of policy attributes to set (e.g., allowed_operations, allowed_resources).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbManagementAccessPolicy -Name "ops-policy" -Attributes @{ }

        Creates a new management access policy named "ops-policy" with default attributes.
    .EXAMPLE
        New-PfbManagementAccessPolicy -Name "readonly-access" -Attributes @{ allowed_operations = @("read") }

        Creates a new read-only management access policy.
    .EXAMPLE
        New-PfbManagementAccessPolicy -Name "test-policy" -Attributes @{ } -WhatIf

        Shows what would happen if the policy were created without making changes.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)] [string]$Name,
        [Parameter()] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $body = if ($Attributes) { $Attributes } else { @{} }
    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create management access policy')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'management-access-policies' -Body $body -QueryParams $queryParams
    }
}
