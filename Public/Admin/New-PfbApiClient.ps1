function New-PfbApiClient {
    <#
    .SYNOPSIS
        Creates a new API client on the FlashBlade.
    .DESCRIPTION
        The New-PfbApiClient cmdlet creates a new API client on the connected Pure Storage
        FlashBlade. API clients require a public key. On REST 2.0-2.18, they also require
        a maximum role assignment; from REST 2.19 onward, max_role is deprecated in favour
        of access_policies.

        The typed parameters and the raw -Attributes hashtable are mutually exclusive: they
        live in separate parameter sets, so PowerShell rejects a mixed invocation at bind time
        rather than letting -Attributes silently override an explicitly supplied value.
    .PARAMETER Name
        The name of the API client to create.
    .PARAMETER PublicKey
        The public key for the API client. Required by the API client's POST body schema.
    .PARAMETER MaxRole
        The maximum role assignment for the API client. The API requires this on REST 2.0-2.18;
        it is deprecated in favour of access_policies from REST 2.19 onward.
    .PARAMETER Attributes
        A raw hashtable defining the API client properties. This parameter is mutually exclusive
        with the typed parameters. When using -Attributes, the caller is responsible for supplying
        the required public_key (and max_role on REST 2.0-2.18).
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        New-PfbApiClient -Name 'automation-client' -PublicKey $key -MaxRole 'storage_admin'

        Creates a new API client with the storage_admin role and the specified public key.
    .EXAMPLE
        New-PfbApiClient -Name 'readonly-client' -PublicKey $key

        Creates a new API client with the specified public key. On REST 2.0-2.18, supply
        -MaxRole as well; from REST 2.19 onward, max_role is deprecated in favour of access_policies.
    .EXAMPLE
        New-PfbApiClient -Name 'ops-client' -Attributes @{ max_role = @{ name = 'ops_admin' }; public_key = $key } -Confirm:$false

        Creates a new API client from a hand-rolled body without prompting for confirmation.
        When using -Attributes, the caller is responsible for supplying the required public_key.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'Typed')]
    param(
        [Parameter(ParameterSetName = 'Typed', Mandatory, Position = 0)]
        [Parameter(ParameterSetName = 'Attributes', Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = 'Typed', Mandatory)]
        [string]$PublicKey,

        [Parameter(ParameterSetName = 'Typed')]
        [string]$MaxRole,

        [Parameter(ParameterSetName = 'Attributes', Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        $body = $Attributes.Clone()
    }
    else {
        $body = @{ public_key = $PublicKey }
        # max_role is a scalar reference ({id, name, resource_type}); resource_type
        # is readOnly and must never be sent.
        if ($PSBoundParameters.ContainsKey('MaxRole')) {
            $body['max_role'] = @{ name = $MaxRole }
        }
    }

    $queryParams = @{ 'names' = $Name }

    if ($PSCmdlet.ShouldProcess($Name, 'Create API client')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'api-clients' -Body $body -QueryParams $queryParams
    }
}
