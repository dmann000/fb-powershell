function New-PfbSmbClientRule {
    <#
    .SYNOPSIS
        Creates a new SMB client policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an SMB client policy. Rules define client access restrictions
        for SMB connections including client IP patterns and encryption settings.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER PolicyName
        The name of the SMB client policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the SMB client policy to add the rule to.
    .PARAMETER Client
        Specifies the clients that will be permitted to access the export.
    .PARAMETER Encryption
        Specifies whether the remote client is required to use SMB encryption.
    .PARAMETER Index
        The index within the policy.
    .PARAMETER Permission
        Specifies which read-write client access permissions are allowed for the export.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, encryption, etc.). Mutually
        exclusive with the individual typed parameters above.
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
        New-PfbSmbClientRule -PolicyName "smb-client-01" -Client "10.0.0.0/8" -Encryption "required"

        Creates a rule for a specific subnet with required encryption using typed parameters.
    .EXAMPLE
        New-PfbSmbClientRule -PolicyName "smb-client-01" -Attributes @{ client = "*" }

        Creates a new rule allowing all clients.
    .EXAMPLE
        New-PfbSmbClientRule -PolicyName "smb-client-01" -Attributes @{ client = "10.0.0.0/8"; encryption = "required" }

        Creates a rule for a specific subnet with required encryption.
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
        [ValidateSet('required', 'disabled', 'optional')]
        [string]$Encryption,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [int]$Index,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('rw', 'ro')]
        [string]$Permission,

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
        if ($PSBoundParameters.ContainsKey('Client'))     { $body['client']     = $Client }
        if ($PSBoundParameters.ContainsKey('Encryption')) { $body['encryption'] = $Encryption }
        if ($PSBoundParameters.ContainsKey('Index'))      { $body['index']      = $Index }
        if ($PSBoundParameters.ContainsKey('Permission')) { $body['permission'] = $Permission }
    }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Create SMB client rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'smb-client-policies/rules' -Body $body -QueryParams $queryParams
    }
}
