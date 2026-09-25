#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    tools/lib/PfbGitHubRead.ps1 against a mocked Invoke-RestMethod: no network, no token.
.DESCRIPTION
    The helpers were extracted from scripts/Assert-PfbAgentReadyBrief.ps1, which has no
    tests of its own, and gained a paged variant for tools/Build-PfbBacklog.ps1. What is
    pinned here is what a live run cannot show on demand: a rate-limit 403 and a permission
    403 read differently, a full single page refuses to answer, both -FollowRelLink output
    shapes flatten to the same records, and the page ceiling throws only when something is
    really left behind it.

    EDITION-GATED, BUT NOT WITH #Requires. The library is #Requires -Version 7.0, so every
    Describe carries -Skip:($PSVersionTable.PSVersion.Major -lt 7) and the file-level
    BeforeAll guards its own dot-source: a skipped Describe does not stop a file-level
    BeforeAll from running. A #Requires here would take the file out of the 5.1 run
    entirely, and scripts/Assert-PfbTestCoverage.ps1 fails a file that contributes no tests.
    The 5.1 skip count is pinned in Tests/coverage-baseline.psd1.

    Fixture records are PSCustomObject, never hashtables: a hashtable is IEnumerable and
    would be expanded as a page, which no real REST record ever is.
#>

BeforeAll {
    $script:isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    if ($script:isPwsh7) {
        . (Join-Path (Join-Path (Join-Path $script:repoRoot 'tools') 'lib') 'PfbGitHubRead.ps1')
    }

    function Build-TestRecord {
        param([int]$Number)
        [PSCustomObject]@{ number = $Number; title = "Issue $Number" }
    }

    # One page as Invoke-RestMethod writes it: the page's array as ONE pipeline object.
    function Build-TestPage {
        param([int]$From, [int]$Count)
        $records = @(for ($i = $From; $i -lt $From + $Count; $i++) { Build-TestRecord -Number $i })
        , $records
    }

    # The exception Invoke-RestMethod throws on an HTTP error status in pwsh 7.
    function Get-TestHttpError {
        param([int]$Status, [string]$Remaining)
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        if ($Remaining) { $response.Headers.Add('x-ratelimit-remaining', $Remaining) }
        [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Status.", $response)
    }

    # Invoke-RestMethod writes -ResponseHeadersVariable into its CALLER's scope. A mock runs
    # some scopes further down (Pester's own frames sit in between), so this walks up to the
    # first scope that already holds the variable -- the library initialises it to $null
    # before the call for exactly this reason -- instead of hard-coding a depth that is
    # Pester's business. Measured: three scopes up from a mock body on Pester 6.0.1.
    function Set-TestResponseHeader {
        param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)]$Value)
        for ($depth = 1; $depth -lt 64; $depth++) {
            try { $null = Get-Variable -Name $Name -Scope $depth -ErrorAction Stop }
            catch [System.Management.Automation.ItemNotFoundException] { continue }
            catch { break }
            Set-Variable -Name $Name -Value $Value -Scope $depth
            return
        }
        throw "No caller scope holds `$$Name. The library must initialise it before calling Invoke-RestMethod."
    }
}

Describe 'Invoke-PfbGitHubApi' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'reports a rate-limit 403 as a quota, not as a failure to fix' {
        Mock Invoke-RestMethod { throw (Get-TestHttpError -Status 403 -Remaining '0') }
        { Invoke-PfbGitHubApi -Path 'repos/o/r/issues' -UserAgent 'pfb-test' } |
            Should -Throw -ExpectedMessage 'GitHub rate limit exhausted while reading repos/o/r/issues.*'
    }

    It 'reports a permission 403 with its status, and never as a rate limit' {
        Mock Invoke-RestMethod { throw (Get-TestHttpError -Status 403 -Remaining '4999') }
        $message = ''
        try { $null = Invoke-PfbGitHubApi -Path 'repos/o/r/issues' -UserAgent 'pfb-test' }
        catch { $message = $_.Exception.Message }
        $message | Should -BeLike 'GET https://api.github.com/repos/o/r/issues failed with HTTP 403: *'
        $message | Should -Not -BeLike '*rate limit*'
    }

    It 'names the URI when the failure carries no HTTP response at all' {
        Mock Invoke-RestMethod { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }
        { Invoke-PfbGitHubApi -Path 'x' -UserAgent 'pfb-test' } |
            Should -Throw -ExpectedMessage 'GET https://api.github.com/x failed: No such host is known.'
    }

    It 'sends a GET with the User-Agent it is given, and a bearer header only when there is a token' {
        Mock Invoke-RestMethod { $null }
        $null = Invoke-PfbGitHubApi -Path 'x' -UserAgent 'pfb-test-agent' -BearerToken 'abc123'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Get' -and $Uri -ceq 'https://api.github.com/x' -and
            $Headers['User-Agent'] -ceq 'pfb-test-agent' -and $Headers['Authorization'] -ceq 'Bearer abc123' -and
            $Headers['Accept'] -ceq 'application/vnd.github+json' -and $Headers['X-GitHub-Api-Version'] -ceq '2022-11-28'
        }
        $null = Invoke-PfbGitHubApi -Path 'x' -UserAgent 'pfb-test-agent'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { -not $Headers.ContainsKey('Authorization') }
    }

    It 'makes -UserAgent mandatory on <Command>, with no default to fall back on' -ForEach @(
        @{ Command = 'Invoke-PfbGitHubApi' }
        @{ Command = 'Invoke-PfbGitHubList' }
        @{ Command = 'Invoke-PfbGitHubPagedList' }
    ) {
        $parameter = (Get-Command -Name $Command).Parameters['UserAgent']
        @($parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }
}

Describe 'Invoke-PfbGitHubList' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'throws on a full page, because a full page may not be the whole list' {
        Mock Invoke-RestMethod { Build-TestPage -From 1 -Count 100 }
        { Invoke-PfbGitHubList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list' } |
            Should -Throw -ExpectedMessage 'The test list returned a full page of 100*'
    }

    It 'returns a short page as flat records' {
        Mock Invoke-RestMethod { Build-TestPage -From 1 -Count 99 }
        $records = @(Invoke-PfbGitHubList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list')
        $records.Count | Should -Be 99
        $records[98].number | Should -Be 99
        ($records[0] -is [System.Collections.IEnumerable]) | Should -BeFalse
    }
}

Describe 'Invoke-PfbGitHubPagedList' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'flattens one page, which Invoke-RestMethod returns as flat records' {
        Mock Invoke-RestMethod { Build-TestPage -From 1 -Count 3 }
        $records = @(Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list')
        $records.Count | Should -Be 3
        @($records | ForEach-Object { $_.number }) -join ',' | Should -BeExactly '1,2,3'
    }

    It 'flattens several pages, which Invoke-RestMethod returns as an array of page arrays' {
        Mock Invoke-RestMethod {
            Build-TestPage -From 1 -Count 100
            Build-TestPage -From 101 -Count 100
            Build-TestPage -From 201 -Count 5
        }
        # Control: the mock really delivers the nested shape. Without this, a mock that
        # flattened by itself would let the assertion below pass without testing anything.
        $raw = Invoke-RestMethod -Uri 'https://example.invalid'
        @($raw).Count | Should -Be 3

        $records = @(Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list')
        $records.Count | Should -Be 205
        $records[204].number | Should -Be 205
        @($records | Where-Object { $_ -is [System.Collections.IEnumerable] }).Count | Should -Be 0
    }

    It 'returns nothing, without throwing, for an empty list' {
        Mock Invoke-RestMethod { , @() }
        @(Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list').Count | Should -Be 0
    }

    It 'throws when the last page read still links to a next page' {
        Mock Invoke-RestMethod {
            Set-TestResponseHeader -Name $ResponseHeadersVariable -Value @{
                Link = @('<https://api.github.com/x?page=3>; rel="next", <https://api.github.com/x?page=1>; rel="prev"')
            }
            Build-TestPage -From 1 -Count 100
            Build-TestPage -From 101 -Count 100
        }
        { Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list' -MaximumPage 2 } |
            Should -Throw -ExpectedMessage 'The test list has more than 2 page(s)*'
    }

    It 'does not throw for exactly the ceiling of full pages when nothing follows them' {
        Mock Invoke-RestMethod {
            Set-TestResponseHeader -Name $ResponseHeadersVariable -Value @{
                Link = @('<https://api.github.com/x?page=9>; rel="prev", <https://api.github.com/x?page=1>; rel="first"')
            }
            for ($p = 0; $p -lt 10; $p++) { Build-TestPage -From ($p * 100 + 1) -Count 100 }
        }
        @(Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list').Count | Should -Be 1000
    }

    It 'asks Invoke-RestMethod to follow rel links up to the ceiling, and reads the headers back' {
        Mock Invoke-RestMethod { , @() }
        $null = Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list' -MaximumPage 7
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $FollowRelLink -and $MaximumFollowRelLink -eq 7 -and $ResponseHeadersVariable -ceq 'pfbGitHubPageHeader' -and
            $Method -eq 'Get' -and $Uri -ceq 'https://api.github.com/x'
        }
    }

    It 'maps a rate-limit 403 the same way a single GET does' {
        Mock Invoke-RestMethod { throw (Get-TestHttpError -Status 403 -Remaining '0') }
        { Invoke-PfbGitHubPagedList -Path 'x' -UserAgent 'pfb-test' -Description 'The test list' } |
            Should -Throw -ExpectedMessage 'GitHub rate limit exhausted while reading x.*'
    }
}

Describe 'ConvertTo-PfbGitHubRecordList and Get-PfbGitHubHeaderValue' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'throws when a record is nested more than one level deep' {
        $inner = [object[]]@(Build-TestRecord -Number 1)
        $page = [object[]]@(, $inner)
        { ConvertTo-PfbGitHubRecordList -Response ([object[]]@(, $page)) -Description 'The test list' } |
            Should -Throw -ExpectedMessage 'The test list came back nested*'
    }

    It 'reads a header case-insensitively from the dictionary shape pwsh returns' {
        $dictionary = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new()
        $dictionary.Add('link', [string[]]@('<a>; rel="next"'))
        Get-PfbGitHubHeaderValue -Header $dictionary -Name 'Link' | Should -BeExactly '<a>; rel="next"'
        Get-PfbGitHubHeaderValue -Header $dictionary -Name 'X-Missing' | Should -BeExactly ''
        Get-PfbGitHubHeaderValue -Header $null -Name 'Link' | Should -BeExactly ''
    }
}
