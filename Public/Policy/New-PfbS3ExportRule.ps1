function New-PfbS3ExportRule {
    <#
    .SYNOPSIS
        Creates a new S3 export policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an S3 export policy. Rules define client access
        permissions and export settings within the policy. Specify the target
        policy by name or ID and provide rule properties via typed parameters or
        the Attributes parameter.

        Unlike the other rule-POST endpoints, `POST /s3-export-policies/rules` requires
        the caller to supply the new rule's name via the required `-Name` query
        parameter -- the server does not assign it.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER PolicyName
        The name of the S3 export policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the S3 export policy to add the rule to.
    .PARAMETER Name
        The name(s) to assign to the new rule. Required -- this endpoint does not
        server-assign the rule name.
    .PARAMETER Actions
        The list of actions granted by this rule.
    .PARAMETER Effect
        Effect of this rule.
    .PARAMETER Resources
        The list of resources from the account to which this rule applies to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, access, permission, etc.).
        Mutually exclusive with the individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbS3ExportRule -PolicyName "s3-export-01" -Name "rule-1" -Effect "allow" -Actions "s3:GetObject" -Resources "bucket1/*"

        Creates a new rule granting read access to a bucket using typed parameters.
    .EXAMPLE
        New-PfbS3ExportRule -PolicyName "s3-export-01" -Name "rule-1" -Attributes @{ client = "*"; access = "root-squash"; permission = "rw" }

        Creates a new rule allowing all clients with root-squash and read-write access.
    .EXAMPLE
        New-PfbS3ExportRule -PolicyId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Name "rule-2" -Attributes @{ client = "*"; permission = "ro" }

        Creates a read-only rule by policy ID.
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

        [Parameter(Mandatory)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string[]]$Actions,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string]$Effect,

        [Parameter(ParameterSetName = 'ByPolicyNameIndividual')]
        [Parameter(ParameterSetName = 'ByPolicyIdIndividual')]
        [string[]]$Resources,

        [Parameter(ParameterSetName = 'ByPolicyNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByPolicyIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($PolicyName) { $queryParams['policy_names'] = $PolicyName }
    if ($PolicyId)   { $queryParams['policy_ids']   = $PolicyId }
    $queryParams['names'] = $Name -join ','

    if ($PSCmdlet.ParameterSetName -like '*Attributes') {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Actions'))   { $body['actions']   = @($Actions) }
        if ($PSBoundParameters.ContainsKey('Effect'))    { $body['effect']    = $Effect }
        if ($PSBoundParameters.ContainsKey('Resources')) { $body['resources'] = @($Resources) }
    }

    $target = if ($PolicyName) { $PolicyName } else { $PolicyId }

    if ($PSCmdlet.ShouldProcess($target, 'Create S3 export rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 's3-export-policies/rules' -Body $body -QueryParams $queryParams
    }
}
