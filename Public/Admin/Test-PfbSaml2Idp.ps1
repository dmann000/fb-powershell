function Test-PfbSaml2Idp {
    <#
    .SYNOPSIS
        Tests a SAML2 identity provider configuration on the FlashBlade.
    .DESCRIPTION
        The Test-PfbSaml2Idp cmdlet runs a connectivity and configuration test against a SAML2
        identity provider on the connected FlashBlade. Returns test results including
        connectivity status, metadata validation, and any errors encountered. The IdP(s) to test
        can be identified by name or ID, and names accept pipeline input by property name.
    .PARAMETER Name
        One or more names of SAML2 identity providers to test.
    .PARAMETER Id
        One or more IDs of SAML2 identity providers to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbSaml2Idp -Name "adfs-prod"

        Tests the SAML2 identity provider named "adfs-prod".
    .EXAMPLE
        Test-PfbSaml2Idp -Id "abc12345-6789-0abc-def0-123456789abc"

        Tests the SAML2 identity provider identified by ID.
    .EXAMPLE
        $results = Test-PfbSaml2Idp -Name "adfs-prod"; $results.success

        Tests the SAML2 IdP and checks whether the test succeeded.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName', ValueFromPipelineByPropertyName)]
        [string[]]$Name,
        [Parameter(ParameterSetName = 'ById')] [string[]]$Id,
        [Parameter()] [PSCustomObject]$Array
    )

    begin {
        Assert-PfbConnection -Array ([ref]$Array)
        $allNames = [System.Collections.Generic.List[string]]::new()
        $allIds   = [System.Collections.Generic.List[string]]::new()
    }

    process {
        if ($Name) { foreach ($n in $Name) { $allNames.Add($n) } }
        if ($Id)   { foreach ($i in $Id)   { $allIds.Add($i) } }
    }

    end {
        $queryParams = @{}
        if ($allNames.Count -gt 0) { $queryParams['names'] = $allNames -join ',' }
        if ($allIds.Count -gt 0)   { $queryParams['ids']   = $allIds -join ',' }

        if (Test-PfbEmptyPipelineRead -Caller $PSCmdlet -QueryParams $queryParams) { return }
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'sso/saml2/idps/test' -QueryParams $queryParams -AutoPaginate
    }
}
