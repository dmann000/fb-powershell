function New-PfbNetworkAccessRule {
    <#
    .SYNOPSIS
        Creates a new network access policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to a network access policy. Rules define network-level access
        control including client IP ranges, interfaces, protocols, and effect (allow/deny).
    .PARAMETER PolicyName
        The name of the network access policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the network access policy to add the rule to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, effect, interfaces, protocols, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNetworkAccessRule -PolicyName "network-access-01" -Attributes @{ client = "10.0.0.0/8"; effect = "allow" }

        Creates a new rule allowing access from the specified subnet.
    .EXAMPLE
        New-PfbNetworkAccessRule -PolicyName "network-access-01" -Attributes @{ client = "0.0.0.0/0"; effect = "deny"; interfaces = @("management") }

        Creates a rule denying access to management interfaces from all clients.
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

    if ($PSCmdlet.ShouldProcess($target, 'Create network access rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-access-policies/rules' -Body $Attributes -QueryParams $queryParams
    }
}
