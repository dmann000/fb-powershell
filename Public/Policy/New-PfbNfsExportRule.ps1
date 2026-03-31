function New-PfbNfsExportRule {
    <#
    .SYNOPSIS
        Creates a new NFS export policy rule on the FlashBlade.
    .DESCRIPTION
        Adds a new rule to an NFS export policy. Rules define client access permissions
        for NFS exports including client IP/hostname patterns, access level, and security.
    .PARAMETER PolicyName
        The name of the NFS export policy to add the rule to.
    .PARAMETER PolicyId
        The ID of the NFS export policy to add the rule to.
    .PARAMETER Attributes
        A hashtable defining the rule properties (client, access, permission, security, etc.).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbNfsExportRule -PolicyName "nfs-export-01" -Attributes @{ client = "*"; access = "root-squash"; permission = "rw" }

        Creates a new rule allowing all clients with root-squash and read-write access.
    .EXAMPLE
        New-PfbNfsExportRule -PolicyName "nfs-export-01" -Attributes @{ client = "10.0.0.0/8"; access = "no-root-squash"; permission = "rw"; security = @("sys") }

        Creates a rule for a specific subnet with no root squash.
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

    if ($PSCmdlet.ShouldProcess($target, 'Create NFS export rule')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'nfs-export-policies/rules' -Body $Attributes -QueryParams $queryParams
    }
}
