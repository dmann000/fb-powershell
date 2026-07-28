function New-PfbNfsExportRule {
    <#
    .SYNOPSIS
        Creates a new NFS export policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an NFS export policy. Rules define client access permissions
        for NFS exports including client IP/hostname patterns, access level, and security.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER PolicyName
        The name of the NFS export policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the NFS export policy to add the rule to.
    .PARAMETER Access
        Specifies access control for the export.
    .PARAMETER Anongid
        Any user whose GID is affected by an `access` of `root_squash` or `all_squash` will
        have their GID mapped to `anongid`.
    .PARAMETER Anonuid
        Any user whose UID is affected by an `access` of `root_squash` or `all_squash` will
        have their UID mapped to `anonuid`.
    .PARAMETER Atime
        If `true`, after a read operation has occurred, the inode access time is updated
        only under certain conditions.
    .PARAMETER Client
        Specifies the clients that will be permitted to access the export.
    .PARAMETER Fileid32bit
        Whether the file id is 32 bits or not.
    .PARAMETER Index
        The index within the policy.
    .PARAMETER Permission
        Specifies which read-write client access permissions are allowed for the export.
    .PARAMETER Policy
        The name of the policy to which this rule belongs.
    .PARAMETER RequiredTransportSecurity
        Specifies the minimum transport security required for clients to access the export.
    .PARAMETER Secure
        If `true`, prevents NFS access to client connections coming from non-reserved ports.
    .PARAMETER Security
        The security flavors to use for accessing files on this mount point.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, access, permission, security, etc.).
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
        New-PfbNfsExportRule -PolicyName "nfs-export-01" -Client "*" -Access "root-squash" -Permission "rw"

        Creates a new rule allowing all clients with root-squash and read-write access using
        typed parameters.
    .EXAMPLE
        New-PfbNfsExportRule -PolicyName "nfs-export-01" -Attributes @{ client = "*"; access = "root-squash"; permission = "rw" }

        Creates a new rule allowing all clients with root-squash and read-write access.
    .EXAMPLE
        New-PfbNfsExportRule -PolicyName "nfs-export-01" -Attributes @{ client = "10.0.0.0/8"; access = "no-root-squash"; permission = "rw"; security = @("sys") }

        Creates a rule for a specific subnet with no root squash.
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
        [ValidateSet('root-squash', 'all-squash', 'no-squash')]
        [string]$Access,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [long]$Anongid,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [long]$Anonuid,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [Nullable[bool]]$Atime,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string]$Client,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [Nullable[bool]]$Fileid32bit,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [int]$Index,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('rw', 'ro')]
        [string]$Permission,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string]$Policy,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [ValidateSet('tls', 'mutual-tls', 'none')]
        [string]$RequiredTransportSecurity,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [Nullable[bool]]$Secure,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string[]]$Security,

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
        if ($PSBoundParameters.ContainsKey('Access'))      { $body['access']      = $Access }
        if ($PSBoundParameters.ContainsKey('Anongid'))     { $body['anongid']     = $Anongid }
        if ($PSBoundParameters.ContainsKey('Anonuid'))     { $body['anonuid']     = $Anonuid }
        if ($PSBoundParameters.ContainsKey('Atime'))       { $body['atime']       = $Atime }
        if ($PSBoundParameters.ContainsKey('Client'))      { $body['client']      = $Client }
        if ($PSBoundParameters.ContainsKey('Fileid32bit')) { $body['fileid_32bit'] = $Fileid32bit }
        if ($PSBoundParameters.ContainsKey('Index'))       { $body['index']       = $Index }
        if ($PSBoundParameters.ContainsKey('Permission'))  { $body['permission']  = $Permission }
        if ($PSBoundParameters.ContainsKey('Policy'))      { $body['policy']      = @{ name = $Policy } }
        if ($PSBoundParameters.ContainsKey('RequiredTransportSecurity')) { $body['required_transport_security'] = $RequiredTransportSecurity }
        if ($PSBoundParameters.ContainsKey('Secure'))      { $body['secure']      = $Secure }
        if ($PSBoundParameters.ContainsKey('Security'))    { $body['security']    = @($Security) }
    }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Create NFS export rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'nfs-export-policies/rules' -Body $body -QueryParams $queryParams
    }
}
