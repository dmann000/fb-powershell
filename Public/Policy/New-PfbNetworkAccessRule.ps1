function New-PfbNetworkAccessRule {
    <#
    .SYNOPSIS
        Creates a new network access policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to a network access policy. Rules define network-level access
        control including client IP ranges, interfaces, protocols, and effect (allow/deny).

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER PolicyName
        The name of the network access policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the network access policy to add the rule to.
    .PARAMETER Client
        Specifies the clients that will be permitted or denied access to the interface.
    .PARAMETER Effect
        If set to `allow`, the specified client will be permitted to access the specified
        interfaces.
    .PARAMETER Index
        The index within the policy.
    .PARAMETER Interfaces
        Specifies which product interfaces this rule applies to, whether it is permitting
        or denying access.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, effect, interfaces, protocols, etc.).
        Mutually exclusive with the individual typed parameters above.
    .PARAMETER BeforeRuleId
        The ID of the rule to insert this rule before. Cannot be combined with -BeforeRuleName.
    .PARAMETER BeforeRuleName
        The name of the rule to insert this rule before. Cannot be combined with -BeforeRuleId.
    .PARAMETER Versions
        A list of versions used for concurrency control. Ordering matches the policy
        names/IDs query parameter. Fails with a 412 if the resource's current version
        does not match.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNetworkAccessRule -PolicyName "network-access-01" -Client "10.0.0.0/8" -Effect "allow"

        Creates a new rule allowing access from the specified subnet using typed parameters.
    .EXAMPLE
        New-PfbNetworkAccessRule -PolicyName "network-access-01" -Attributes @{ client = "10.0.0.0/8"; effect = "allow" }

        Creates a new rule allowing access from the specified subnet.
    .EXAMPLE
        New-PfbNetworkAccessRule -PolicyName "network-access-01" -Attributes @{ client = "0.0.0.0/0"; effect = "deny"; interfaces = @("management") }

        Creates a rule denying access to management interfaces from all clients.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByPolicyNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByPolicyNameIndividual', Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'ByPolicyNameAttributes',  Mandatory, Position = 0)]
        [string]$PolicyName,

        [Parameter(ParameterSetName = 'ByPolicyIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByPolicyIdAttributes',  Mandatory)]
        [string]$PolicyId,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string]$Client,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('allow', 'deny')]
        [string]$Effect,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [int]$Index,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('management-ssh', 'management-rest-api', 'management-web-ui', 'snmp', 'local-network-superuser-password-access')]
        [string[]]$Interfaces,

        [Parameter(ParameterSetName = 'ByPolicyNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByPolicyIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [string]$BeforeRuleId,
        [Parameter()] [string]$BeforeRuleName,
        [Parameter()] [string[]]$Versions,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    if ($PSBoundParameters.ContainsKey('BeforeRuleId'))   { $queryParams['before_rule_id']   = $BeforeRuleId }
    if ($PSBoundParameters.ContainsKey('BeforeRuleName')) { $queryParams['before_rule_name'] = $BeforeRuleName }
    if ($PSBoundParameters.ContainsKey('Versions'))       { $queryParams['versions']         = $Versions -join ',' }

    if ($PSCmdlet.ParameterSetName -like '*Attributes') {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Client')) { $body['client'] = $Client }
        if ($PSBoundParameters.ContainsKey('Effect')) { $body['effect'] = $Effect }
        if ($PSBoundParameters.ContainsKey('Index'))  { $body['index']  = $Index }
        if ($PSBoundParameters.ContainsKey('Interfaces')) { $body['interfaces'] = @($Interfaces) }
    }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Create network access rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'network-access-policies/rules' -Body $body -QueryParams $queryParams
    }
}
