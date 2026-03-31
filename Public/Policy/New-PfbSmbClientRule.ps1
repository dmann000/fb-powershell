function New-PfbSmbClientRule {
    <#
    .SYNOPSIS
        Creates a new SMB client policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an SMB client policy. Rules define client access restrictions
        for SMB connections including client IP patterns and encryption settings.
    .PARAMETER PolicyName
        The name of the SMB client policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the SMB client policy to add the rule to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, encryption, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSmbClientRule -PolicyName "smb-client-01" -Attributes @{ client = "*" }

        Creates a new rule allowing all clients.
    .EXAMPLE
        New-PfbSmbClientRule -PolicyName "smb-client-01" -Attributes @{ client = "10.0.0.0/8"; encryption = "required" }

        Creates a rule for a specific subnet with required encryption.
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

    if ($PSCmdlet.ShouldProcess($target, 'Create SMB client rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'smb-client-policies/rules' -Body $Attributes -QueryParams $queryParams
    }
}
