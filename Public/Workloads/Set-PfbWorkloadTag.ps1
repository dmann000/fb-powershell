function Set-PfbWorkloadTag {
    <#
    .SYNOPSIS
        Sets (creates or updates) tags on FlashBlade workloads.
    .DESCRIPTION
        PUT batch upsert of tags on the specified workloads. Pass the tag set as an array of
        hashtables. Each tag is { key, value, namespace? }.
    .PARAMETER ResourceName
        Workload name(s) to tag.
    .PARAMETER ResourceId
        Workload ID(s) to tag.
    .PARAMETER Tags
        Array of tag hashtables (1-30 items). Each: @{ key = '...'; value = '...'; namespace = '...' }
    .PARAMETER Array
        FlashBlade connection.
    .EXAMPLE
        Set-PfbWorkloadTag -ResourceName wl1 -Tags @(
            @{ key='team';  value='analytics'; namespace='default' },
            @{ key='env';   value='prod';      namespace='default' }
        )
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(ParameterSetName = 'ByName')]
        [string[]]$ResourceName,

        [Parameter(ParameterSetName = 'ById')]
        [string[]]$ResourceId,

        [Parameter(Mandatory)]
        [ValidateCount(1, 30)]
        [hashtable[]]$Tags,

        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    $queryParams = @{}
    if ($ResourceName) { $queryParams['resource_names'] = $ResourceName -join ',' }
    if ($ResourceId)   { $queryParams['resource_ids']   = $ResourceId -join ',' }

    # -InputObject, NOT the pipeline. The pipeline unrolls $Tags, so a one-element
    # [hashtable[]] -- which [ValidateCount(1, 30)] explicitly permits -- reaches
    # ConvertTo-Json as a bare hashtable and serialises to a JSON object instead of a
    # one-element array. The endpoint requires an array (minItems 1), so the single-tag
    # case was rejected on the wire. -InputObject serialises the collection as a whole.
    $jsonBody = ConvertTo-Json -InputObject $Tags -Depth 5

    if ($PSCmdlet.ShouldProcess(($ResourceName + $ResourceId -join ', '), "Apply $($Tags.Count) tag(s)")) {
        # Direct REST call bypassing the hashtable-only -Body parameter on Invoke-PfbApiRequest.
        $apiVer = $Array.ApiVersion
        $qs = ConvertTo-PfbQueryString -Parameters $queryParams
        $uri = "https://$($Array.Endpoint)/api/${apiVer}/workloads/tags/batch${qs}"
        $headers = @{ 'Content-Type' = 'application/json'; 'x-auth-token' = $Array.AuthToken }
        $restParams = @{ Method = 'PUT'; Uri = $uri; Headers = $headers; Body = $jsonBody }
        if ($Array.SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
            $restParams['SkipCertificateCheck'] = $true
        }
        Write-Verbose "FlashBlade API: PUT $uri"
        Invoke-RestMethod @restParams
    }
}
