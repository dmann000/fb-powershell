function New-PfbSmbShareRule {
    <#
    .SYNOPSIS
        Creates a new SMB share policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an SMB share policy. Rules define share-level access control
        for SMB shares including principal, permission, and change settings.
    .PARAMETER PolicyName
        The name of the SMB share policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the SMB share policy to add the rule to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (principal, change, read, full_control, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSmbShareRule -PolicyName "smb-share-01" -Attributes @{ principal = "Everyone"; change = "allow" }

        Creates a new rule granting change access to everyone.
    .EXAMPLE
        New-PfbSmbShareRule -PolicyName "smb-share-01" -Attributes @{ principal = "DOMAIN\\Admins"; full_control = "allow" }

        Creates a rule granting full control to a domain group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyName', Mandatory, Position = 0)]
        [string]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyId', Mandatory)]
        [string]$PolicyId,

        [Parameter(Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Create SMB share rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'smb-share-policies/rules' -Body $Attributes -QueryParams $queryParams
    }
}
