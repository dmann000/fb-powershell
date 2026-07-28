function New-PfbSmbShareRule {
    <#
    .SYNOPSIS
        Creates a new SMB share policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an SMB share policy. Rules define share-level access control
        for SMB shares including principal, permission, and change settings.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER PolicyName
        The name of the SMB share policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the SMB share policy to add the rule to.
    .PARAMETER Change
        The state of the principal's Change access permission.
    .PARAMETER FullControl
        The state of the principal's Full Control access permission.
    .PARAMETER Principal
        The user or group who is the subject of this rule, and optionally their domain.
    .PARAMETER Read
        The state of the principal's Read access permission.
    .PARAMETER Attributes
        A hashtable defining the rule properties (principal, change, read, full_control, etc.).
        Mutually exclusive with the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbSmbShareRule -PolicyName "smb-share-01" -Principal "Everyone" -Change "allow"

        Creates a new rule granting change access to everyone using typed parameters.
    .EXAMPLE
        New-PfbSmbShareRule -PolicyName "smb-share-01" -Attributes @{ principal = "Everyone"; change = "allow" }

        Creates a new rule granting change access to everyone.
    .EXAMPLE
        New-PfbSmbShareRule -PolicyName "smb-share-01" -Attributes @{ principal = "DOMAIN\\Admins"; full_control = "allow" }

        Creates a rule granting full control to a domain group.
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
        [ValidateSet('allow', 'deny')]
        [string]$Change,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('allow', 'deny')]
        [string]$FullControl,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string]$Principal,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('allow', 'deny')]
        [string]$Read,

        [Parameter(ParameterSetName = 'ByPolicyNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByPolicyIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }

    if ($PSCmdlet.ParameterSetName -like '*Attributes') {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Change'))      { $body['change']       = $Change }
        if ($PSBoundParameters.ContainsKey('FullControl')) { $body['full_control'] = $FullControl }
        if ($PSBoundParameters.ContainsKey('Principal'))   { $body['principal']    = $Principal }
        if ($PSBoundParameters.ContainsKey('Read'))        { $body['read']         = $Read }
    }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Create SMB share rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'smb-share-policies/rules' -Body $body -QueryParams $queryParams
    }
}
