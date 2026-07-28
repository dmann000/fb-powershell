function Update-PfbApiClient {
    <#
    .SYNOPSIS
        Updates an API client on the FlashBlade.
    .DESCRIPTION
        The Update-PfbApiClient cmdlet modifies an existing API client on the connected
        Everpure FlashBlade.

        Note that `PATCH /api-clients` reuses the full ApiClient resource schema. Of its nine
        properties, seven are read-only and `max_role` is deprecated rather than read-only,
        which leaves `enabled` as the only settable field this cmdlet exposes as a typed
        parameter.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value.
    .PARAMETER Name
        The name of the API client to update.
    .PARAMETER Id
        The ID of the API client to update.
    .PARAMETER Enabled
        If $true, the API client is permitted to exchange ID Tokens for access tokens.
    .PARAMETER Attributes
        A hashtable of properties to update on the API client. Mutually exclusive with the
        individual typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Update-PfbApiClient -Name 'automation-client' -Enabled $true

        Enables the API client named 'automation-client' using a typed parameter.
    .EXAMPLE
        Update-PfbApiClient -Name 'automation-client' -Attributes @{ enabled = $true }

        Enables the API client named 'automation-client'.
    .EXAMPLE
        Update-PfbApiClient -Id '12345678-abcd-efgh-ijkl-123456789012' -Enabled $false

        Disables an API client by ID.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',
                   DefaultParameterSetName = 'ByNameIndividual')]
    param(
        [Parameter(ParameterSetName = 'ByNameIndividual', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Parameter(ParameterSetName = 'ByNameAttributes',  Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ByIdIndividual', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',  Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByNameIndividual')]
        [Parameter(ParameterSetName = 'ByIdIndividual')]
        [Nullable[bool]]$Enabled,

        [Parameter(ParameterSetName = 'ByNameAttributes', Mandatory)]
        [Parameter(ParameterSetName = 'ByIdAttributes',   Mandatory)]
        [hashtable]$Attributes,

        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
    }

    process {
        $queryParams = @{}
        if ($Name) { $queryParams['names'] = $Name }
        if ($Id)   { $queryParams['ids']   = $Id }

        if ($PSCmdlet.ParameterSetName -like '*Attributes') {
            $body = $Attributes
        }
        else {
            # Every body parameter is guarded by ContainsKey, never by truthiness -- see the
            # canonical explanation in Update-PfbAdmin.ps1.
            $body = @{}
            if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }
        }

        $target = if ($Name) { $Name } else { $Id }
        if ($PSCmdlet.ShouldProcess($target, 'Update API client')) {
            Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'api-clients' -Body $body -QueryParams $queryParams
        }
    }
}
