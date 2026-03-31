function New-PfbS3ExportRule {
    <#
    .SYNOPSIS
        Creates a new S3 export policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an S3 export policy. Rules define client access
        permissions and export settings within the policy. Specify the target
        policy by name or ID and provide rule properties via the Attributes parameter.
    .PARAMETER PolicyName
        The name of the S3 export policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the S3 export policy to add the rule to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, access, permission, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbS3ExportRule -PolicyName "s3-export-01" -Attributes @{ client = "*"; access = "root-squash"; permission = "rw" }

        Creates a new rule allowing all clients with root-squash and read-write access.
    .EXAMPLE
        New-PfbS3ExportRule -PolicyName "s3-export-01" -Attributes @{ client = "10.0.0.0/8"; access = "no-root-squash"; permission = "rw" }

        Creates a rule for a specific subnet with no root squash.
    .EXAMPLE
        New-PfbS3ExportRule -PolicyId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Attributes @{ client = "*"; permission = "ro" }

        Creates a read-only rule by policy ID.
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

    if ($PSCmdlet.ShouldProcess($target, 'Create S3 export rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 's3-export-policies/rules' -Body $Attributes -QueryParams $queryParams
    }
}
