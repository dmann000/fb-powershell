#Requires -Version 7.0
<#
.SYNOPSIS
    Read-only GitHub REST helpers, shared by the scripts that read this repository's issues.
.DESCRIPTION
    Extracted from scripts/Assert-PfbAgentReadyBrief.ps1 so tools/Build-PfbBacklog.ps1 reads
    issues the same way, and extended with a paged list:

      Invoke-PfbGitHubApi        one GET.
      Invoke-PfbGitHubList       one page; a FULL page throws. That is the brief gate's
                                 semantics: there, a full page is itself the finding.
      Invoke-PfbGitHubPagedList  every page, following Link: rel="next" up to a ceiling
                                 that throws rather than truncates.

    NO GITHUB CLI, AND NO CREDENTIAL REQUIRED. The repository is public, so every endpoint
    used here answers anonymously. A token only raises the rate limit (60 requests an hour
    per source IP anonymously, 1,000 with the workflow's GITHUB_TOKEN); it grants nothing.

    -UserAgent IS MANDATORY, WITH NO DEFAULT. GitHub rejects a request with no User-Agent,
    and naming the caller is what makes an abuse-detection response traceable to one
    script rather than to "some PowerShell". A shared default would erase that.

    Every request is a GET. Nothing here can write.

    TARGETS POWERSHELL 7: -FollowRelLink and -ResponseHeadersVariable do not exist on 5.1,
    and nothing here ships in the module. The syntax stays 5.1-parseable all the same,
    because PSUseCompatibleSyntax (targets 5.1 and 7.0) is held at zero repo-wide and reads
    neither #Requires nor version guards. Pure ASCII: PSUseBOMForUnicodeEncodedFile is held
    at zero.
#>

$script:PfbGitHubApiRoot = 'https://api.github.com'
$script:PfbPageSize = 100

# The most pages Invoke-PfbGitHubPagedList follows: 1,000 records at the page size above,
# the same ceiling tools/New-PfbDriftIssue.ps1 puts on `gh issue list`. Measured on pwsh
# 7.6.6: -MaximumFollowRelLink 2 returns exactly two pages, so this is a page count.
$script:PfbGitHubMaxPage = 10

function Get-PfbGitHubRequestHeader {
    <#
    .SYNOPSIS
        The request headers every call sends.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$UserAgent,
        [string]$BearerToken
    )

    $headers = @{
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = $UserAgent
    }
    if ($BearerToken) { $headers['Authorization'] = "Bearer $BearerToken" }
    return $headers
}

function Get-PfbGitHubFailureMessage {
    <#
    .SYNOPSIS
        The message to throw for a failed GET, with a rate-limit 403 told apart from the rest.
    .DESCRIPTION
        Rate limiting is separated from every other 403 on purpose. A quota 403 and a
        permissions 403 demand opposite responses -- wait, versus fix the workflow -- and
        GitHub distinguishes them only by the x-ratelimit-remaining header, which is why
        this reads the header instead of matching on the message text.

        The Response member is looked up through PSObject.Properties, so a failure that
        carries no HTTP response (DNS, TLS, a thrown string) yields the generic message
        instead of a StrictMode error about a missing property.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Uri
    )

    $exception = $ErrorRecord.Exception
    $status = ''
    $remaining = ''
    $responseProperty = $exception.PSObject.Properties['Response']
    if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) {
        $response = $responseProperty.Value
        $status = [string][int]$response.StatusCode
        $header = $null
        if ($response.Headers.TryGetValues('x-ratelimit-remaining', [ref]$header)) {
            $remaining = [string]@($header)[0]
        }
    }
    if ($status -eq '403' -and $remaining -eq '0') {
        return "GitHub rate limit exhausted while reading $Path. Unauthenticated callers get 60 requests an hour per source IP; pass -Token or set GITHUB_TOKEN to raise it to 1,000. This is a quota, not a missing label -- do not read it as a finding."
    }
    $httpText = ''
    if ($status) { $httpText = " with HTTP $status" }
    return "GET $Uri failed${httpText}: $($exception.Message)"
}

function Invoke-PfbGitHubApi {
    <#
    .SYNOPSIS
        One GET against the REST API, with the token applied when there is one.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$UserAgent,
        [string]$BearerToken
    )

    $headers = Get-PfbGitHubRequestHeader -UserAgent $UserAgent -BearerToken $BearerToken
    $uri = "$script:PfbGitHubApiRoot/$Path"
    try {
        return Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
    }
    catch {
        throw (Get-PfbGitHubFailureMessage -ErrorRecord $_ -Path $Path -Uri $uri)
    }
}

function Invoke-PfbGitHubList {
    <#
    .SYNOPSIS
        A list endpoint, with a truncation guard instead of pagination.
    .DESCRIPTION
        `gh api --paginate` follows Link headers, and a plain Invoke-RestMethod call does
        not, so a result that exactly fills a page is indistinguishable here from one that
        has more behind it. Rather than follow links for an endpoint that is meant to hold a
        handful of issues, this refuses to answer when the page is full. For the brief gate
        (scripts/Assert-PfbAgentReadyBrief.ps1), a full page is itself the finding: a
        hundred issues labelled status:agent-ready means the label has stopped meaning
        anything, which is the defect that gate exists to catch.
        Invoke-PfbGitHubPagedList below is the variant for callers that want every page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$UserAgent,
        [string]$BearerToken,
        [Parameter(Mandatory = $true)][string]$Description
    )

    # THE ASSIGNMENT IS LOAD-BEARING. Invoke-RestMethod writes a JSON array to the pipeline
    # as ONE non-enumerated object, so `@(Invoke-PfbGitHubApi ...)` yields a single element
    # that IS the array rather than the array's elements. Measured: @(call) gives Count 1
    # with elem0 of type Object[], while assigning first and then wrapping gives Count 2 of
    # PSCustomObject. Assigning to a variable and wrapping that is what flattens it.
    #
    # This is not a style preference. With the nested shape, `$issue.number` returns an
    # ARRAY of every issue number via member enumeration, and the truncation guard below
    # compares 1 against the page size and can never fire. Both failures are silent in the
    # direction of passing.
    $response = Invoke-PfbGitHubApi -Path $Path -UserAgent $UserAgent -BearerToken $BearerToken
    $page = @($response)

    if ($page.Count -ge $script:PfbPageSize) {
        throw "$Description returned a full page of $script:PfbPageSize, so there may be more behind it and this gate would silently judge only the first page. Paginate this call before trusting the result."
    }

    # A self-check on the shape the comment above describes, because the nested form is
    # indistinguishable from the flat one until something casts a member to [int]. Three
    # lines here turn a silent wrong answer into a named failure.
    foreach ($element in $page) {
        if ($element -is [System.Collections.IEnumerable] -and $element -isnot [string]) {
            throw "$Description came back nested: an element is a collection rather than a record. The response was not flattened, so member access would enumerate across records instead of reading one."
        }
    }

    return @($page)
}

function Get-PfbGitHubHeaderValue {
    <#
    .SYNOPSIS
        One response header's value as a single string; '' when it is absent.
    .DESCRIPTION
        -ResponseHeadersVariable holds a Dictionary[string, IEnumerable[string]] on pwsh 7.6
        (measured), so a value is a list of strings, joined here with ', '. Names compare
        case-insensitively, as HTTP header names do, and the keys are walked rather than
        indexed, so a hashtable (as a test passes) and the dictionary behave alike.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()]$Header,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Header) { return '' }
    foreach ($key in @($Header.Keys)) {
        if ([string]$key -eq $Name) { return (@($Header[$key]) -join ', ') }
    }
    return ''
}

function ConvertTo-PfbGitHubRecordList {
    <#
    .SYNOPSIS
        A -FollowRelLink response as flat records, whatever the page count.
    .DESCRIPTION
        THE SHAPE DEPENDS ON THE PAGE COUNT (measured, pwsh 7.6.6). One page comes back as
        the page's own array of records; several pages come back as an array of page
        arrays. So this expands any element that is a non-string IEnumerable (a REST
        record is a PSCustomObject, which never is) and then asserts that no element is
        still a collection. A deeper nesting becomes a named failure instead of member
        enumeration silently reading across records (see Invoke-PfbGitHubList).
    .OUTPUTS
        The records, one at a time; wrap the call in @().
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Response,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($element in @($Response)) {
        if ($null -eq $element) { continue }
        if ($element -is [System.Collections.IEnumerable] -and $element -isnot [string]) {
            foreach ($inner in $element) {
                if ($null -ne $inner) { $records.Add($inner) }
            }
        }
        else { $records.Add($element) }
    }
    foreach ($record in $records) {
        if ($record -is [System.Collections.IEnumerable] -and $record -isnot [string]) {
            throw "$Description came back nested more than one level deep: after flattening pages, an element is still a collection rather than a record."
        }
    }
    foreach ($record in $records) { $record }
}

function Invoke-PfbGitHubPagedList {
    <#
    .SYNOPSIS
        Every page of a list endpoint, flattened, with a ceiling that throws instead of truncating.
    .DESCRIPTION
        Invoke-RestMethod -FollowRelLink follows Link: rel="next" by itself. What it does
        not do is say when it stopped early: reaching -MaximumFollowRelLink raises no
        warning and no error, and the result is simply short. So the LAST page's Link header
        is read back through -ResponseHeadersVariable, which holds the last response's
        headers (measured). A rel="next" still on it means more was left: that throws.
        Counting pages would not do, because exactly -MaximumPage full pages with nothing
        behind them is a complete answer, and a count cannot tell it from a truncated one.

        The headers variable is initialised before the call. Invoke-RestMethod does not need
        that, but a Pester mock can only write it by finding it in a caller's scope
        (Tests/PfbGitHubRead.Tests.ps1), and $null is also the right value if the call throws.
    .OUTPUTS
        The records, one at a time; wrap the call in @().
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$UserAgent,
        [string]$BearerToken,
        [Parameter(Mandatory = $true)][string]$Description,
        [ValidateRange(1, 100)][int]$MaximumPage = $script:PfbGitHubMaxPage
    )

    $headers = Get-PfbGitHubRequestHeader -UserAgent $UserAgent -BearerToken $BearerToken
    $uri = "$script:PfbGitHubApiRoot/$Path"
    $pfbGitHubPageHeader = $null
    try {
        # Assigned, never wrapped at the call: see THE ASSIGNMENT IS LOAD-BEARING above.
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -FollowRelLink `
            -MaximumFollowRelLink $MaximumPage -ResponseHeadersVariable 'pfbGitHubPageHeader' -ErrorAction Stop
    }
    catch {
        throw (Get-PfbGitHubFailureMessage -ErrorRecord $_ -Path $Path -Uri $uri)
    }

    $link = Get-PfbGitHubHeaderValue -Header $pfbGitHubPageHeader -Name 'Link'
    if ($link -match 'rel="next"') {
        throw "$Description has more than $MaximumPage page(s) of results: the last page read still links to a next one, so the list is truncated and anything judged from it would be judged on part of it. Raise -MaximumPage deliberately."
    }
    ConvertTo-PfbGitHubRecordList -Response $response -Description $Description
}
