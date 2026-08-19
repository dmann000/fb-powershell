function Test-PfbActiveDirectory {
    <#
    .SYNOPSIS
        Tests the FlashBlade Active Directory configuration.
    .DESCRIPTION
        The Test-PfbActiveDirectory cmdlet runs a connectivity and configuration test against
        an Active Directory configuration on the connected FlashBlade. Returns
        test results including domain connectivity status, authentication checks, and any errors
        encountered. The AD configuration(s) to test can be identified by name or ID, and names
        accept pipeline input by property name.
    .PARAMETER Name
        One or more names of Active Directory configurations to test.
    .PARAMETER Id
        One or more IDs of Active Directory configurations to test.
    .PARAMETER Array
        The FlashBlade connection object. If not specified, the default connection is used.
    .EXAMPLE
        Test-PfbActiveDirectory -Name "ad1"

        Tests the Active Directory configuration named "ad1".
    .EXAMPLE
        Test-PfbActiveDirectory -Id "abc12345-6789-0abc-def0-123456789abc"

        Tests the Active Directory configuration identified by ID.
    .EXAMPLE
        $results = Test-PfbActiveDirectory -Name "ad1"; $results.success

        Tests the AD configuration and checks whether the test succeeded.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
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
        Invoke-PfbApiRequest -Array $Array -Method GET -Endpoint 'active-directory/test' -QueryParams $queryParams -AutoPaginate
    }
}
