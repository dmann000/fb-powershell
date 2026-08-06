function Connect-PfbArray {
    <#
    .SYNOPSIS
        Connect to a FlashBlade array.
    .DESCRIPTION
        Connect to a FlashBlade array (using supported authentication method) and get an
        access token. Mirrors the Connect-Pfa2Array experience from the FlashArray PowerShell SDK.

        Supported authentication methods:
        - API token (default)
        - Username and password (Credential parameter set)
        - PSCredential object (PSCredential parameter set)
        - OAuth2/JWT certificate-based authentication (Certificate parameter set)

        Username/Password Authentication Flow:
        When using -Password or -Credential, the cmdlet checks whether the array
        supports native REST 2.x username/password login (FlashBlade REST API 2.26 /
        Purity//FB 4.8.1+). If so, it POSTs the credentials to the unversioned /api/login
        endpoint and returns a session token (x-auth-token); the optional long-lived API
        token can be retrieved from /admins/api-tokens for future passwordless
        reconnects. If the array is below that threshold, the cmdlet instead falls back
        to SSH (via the optional Posh-SSH module) to mint an API token using the
        'pureadmin' CLI, then completes login with that token. FlashBlade has never had
        a REST-based way to exchange username/password for a token below this version,
        so SSH is not a convenience fallback here -- it's the only mechanism available.
        Install Posh-SSH with: Install-Module -Name Posh-SSH -Scope CurrentUser -Force

        OAuth2/Certificate Authentication Flow:
        When using -ClientId/-Issuer/-KeyId/-PrivateKeyFile, the cmdlet mints a
        short-lived (5 minute) JWT and exchanges it for an OAuth2 access token. That
        access token's lifetime (access_token_ttl_in_ms) is set per API client by an
        admin on the array -- anywhere from 1 second to 24 hours -- and is not knowable
        in advance. The connection automatically refreshes the access token before it
        expires (and, as a fallback, immediately after a 401 caused by early expiry or
        clock skew), so Certificate-authenticated sessions behave like every other
        authentication method here: no manual reconnect required. See .NOTES for what's
        retained in memory to make this possible.

        Auto-negotiates the highest supported API version unless explicitly specified.
        The connection is cached and becomes the default for subsequent cmdlet calls.
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade array.
    .PARAMETER ApiToken
        The API token for authentication. Generate via the FlashBlade CLI or GUI.
    .PARAMETER Username
        Login name of the array user. For Credential auth: used with -Password.
        For Certificate auth: the JWT 'sub' claim — the array user to act as.
    .PARAMETER Password
        Password for the specified username as a SecureString.
    .PARAMETER Credential
        A PSCredential object containing username and password for authentication.
    .PARAMETER ClientId
        Client ID of the API client registered on the FlashBlade.
        Used for OAuth2 certificate-based authentication.
    .PARAMETER Issuer
        The identity provider issuer string. Must match the 'issuer' field
        configured on the API client. Used as the JWT 'iss' claim.
    .PARAMETER KeyId
        Key ID of the API client. Used as the JWT 'kid' header claim.
    .PARAMETER PrivateKeyFile
        Path to the PEM-encoded RSA private key file that pairs with the
        API client's public key. Supports PKCS#1 and PKCS#8 formats.
    .PARAMETER PrivateKeyPassword
        Password for an encrypted private key file (PKCS#8 encrypted format).
        Only required if the private key is password-protected.
    .PARAMETER ApiVersion
        Force a specific API version (e.g., '2.12'). If not specified, the highest
        supported 2.x version is auto-negotiated.
    .PARAMETER IgnoreCertificateError
        Bypass SSL certificate validation. Common for lab environments with self-signed certs.
    .PARAMETER HttpTimeout
        HTTP request timeout in milliseconds. Default is 30000 (30 seconds).
    .PARAMETER Context
        One or more Fusion context names to use as the durable session default for this
        connection. Names are not resolved at connect time; an invalid name is rejected by
        the array, verbatim, on first use.
    .PARAMETER Kind
        What the -Context names refer to: 'Array' (default), 'Fleet', or 'TopologyGroup'.
    .PARAMETER AllArrays
        Target every array that is a member of the -Context names rather than the named
        objects themselves. Not valid with -Kind Array, which has no members.
    .NOTES
        Certificate/OAuth2 sessions retain -ClientId, -Issuer, -KeyId, -PrivateKeyFile,
        and -PrivateKeyPassword (as a SecureString) on the connection object for the
        session's lifetime, so the access token can be silently re-minted before or
        immediately after it expires. This mirrors the existing precedent of retaining
        -ApiToken for the -Credential/-Password auto-reconnect flow -- same risk class,
        not a new category of exposure.
    .EXAMPLE
        $array = Connect-PfbArray -Endpoint fb01.example.com -ApiToken $token -IgnoreCertificateError

        Connect using an API token with SSL bypass for lab environments.
    .EXAMPLE
        $pw = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
        $array = Connect-PfbArray -Endpoint fb01.example.com -Username "pureuser" -Password $pw -IgnoreCertificateError

        Connect using username and password via the native REST 2.x /api/login endpoint.
    .EXAMPLE
        $cred = Get-Credential
        $array = Connect-PfbArray -Endpoint fb01.example.com -Credential $cred -IgnoreCertificateError

        Connect using a PSCredential object.
    .EXAMPLE
        $array = Connect-PfbArray -Endpoint fb01.example.com -Username "pureuser" `
            -ClientId "9472190-f792-712e-a639-0839fa830922" `
            -Issuer "myapp" -KeyId "e50c1a8f-..." `
            -PrivateKeyFile "C:\keys\fb-private.pem" -IgnoreCertificateError

        Connect using OAuth2 JWT certificate-based authentication.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ApiToken')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [Parameter(Mandatory, ParameterSetName = 'ApiToken', Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$ApiToken,

        [Parameter(ParameterSetName = 'Credential')]
        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [ValidateNotNullOrEmpty()]
        [string]$Username,

        [Parameter(Mandatory, ParameterSetName = 'Credential')]
        [System.Security.SecureString]$Password,

        [Parameter(ParameterSetName = 'Credential')]
        [Parameter(Mandatory, ParameterSetName = 'PSCredential')]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$Issuer,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$KeyId,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$PrivateKeyFile,

        [Parameter(ParameterSetName = 'Certificate')]
        [System.Security.SecureString]$PrivateKeyPassword,

        [Parameter()]
        [string]$ApiVersion,

        [Parameter()]
        [switch]$IgnoreCertificateError,

        [Parameter()]
        [int]$HttpTimeout = 30000,

        # ValidateNotNull, not ValidateNotNullOrEmpty: @() must stay bindable so an explicit
        # empty context remains distinguishable from an unset one. The guard exists for error
        # ATTRIBUTION, not to prevent a hang: measured, an explicitly-supplied $null binds and
        # is then rejected downstream by ConvertTo-PfbContextEntryList blaming -Name, a
        # parameter the caller never typed. (PowerShell prompts for a mandatory parameter only
        # when the argument is ABSENT, never when $null was passed.) Validating here fails at
        # the binder naming -Context, the parameter they did type.
        [Parameter()]
        [ValidateNotNull()]
        [string[]]$Context,

        [Parameter()]
        [ValidateSet('Array', 'Fleet', 'TopologyGroup')]
        [string]$Kind = 'Array',

        [Parameter()]
        [switch]$AllArrays
    )

    # Force TLS 1.2 on PowerShell 5.1 unconditionally -- independent of certificate
    # validation bypass, which is a separate concern.
    Set-PfbTlsProtocol

    # Context composition is a pure parameter check -- no network, no $connection. Validated
    # here so a bad -Kind/-AllArrays pair fails before a login is attempted and before any
    # cache is repointed. The name itself is NOT resolved locally: the wire rejects a bad one
    # loudly and verbatim on first use (spec section 9).
    $contextRequested = $PSBoundParameters.ContainsKey('Context')
    $contextEntries = @()
    if ($contextRequested) {
        $form = Resolve-PfbContextForm -AllArrays:$AllArrays
        # The @(...) wrapper is load-bearing: without it a call emitting nothing assigns $null
        # instead of an empty array, collapsing explicit-empty into unset.
        $contextEntries = @(ConvertTo-PfbContextEntryList -Name $Context -Kind $Kind -Form $form)
        foreach ($entry in $contextEntries) { Assert-PfbContextEntryComposition -Entry $entry }
    }

    # Handle SSL bypass
    if ($IgnoreCertificateError) {
        Set-PfbCertificatePolicy
    }

    # Convert -HttpTimeout (milliseconds) to the whole seconds Invoke-RestMethod/
    # Invoke-WebRequest expect via -TimeoutSec. Round up so a sub-1000ms value never
    # collapses to 0 (TimeoutSec 0 means "no timeout" on some PowerShell versions).
    $timeoutSec = [int][Math]::Ceiling($HttpTimeout / 1000.0)

    # Resolve PSCredential to username/password
    if ($PSCmdlet.ParameterSetName -eq 'PSCredential') {
        $Username = $Credential.UserName
        $Password = $Credential.Password
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Credential' -and $Credential) {
        # Credential set allows optional -Credential alongside -Password
        if (-not $Username) { $Username = $Credential.UserName }
        if (-not $Password) { $Password = $Credential.Password }
    }

    # Discover supported API versions
    $versionUri = "https://${Endpoint}/api/api_version"
    $versionParams = @{
        Method     = 'GET'
        Uri        = $versionUri
        TimeoutSec = $timeoutSec
    }
    if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
        $versionParams['SkipCertificateCheck'] = $true
    }

    try {
        $versionResponse = Invoke-RestMethod @versionParams -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to FlashBlade at '${Endpoint}': $(ConvertTo-PfbApiError -Method 'GET' -Endpoint 'api_version' -ErrorRecord $_)"
    }

    $supportedVersions = $versionResponse.versions

    # Negotiate API version
    if ($ApiVersion) {
        if ($ApiVersion -notin $supportedVersions) {
            throw "API version '${ApiVersion}' is not supported by this FlashBlade. Supported versions: $($supportedVersions -join ', ')"
        }
        $negotiatedVersion = $ApiVersion
    }
    else {
        # Pick the highest 2.x version
        $v2Versions = ConvertTo-PfbVersionObject -Versions $supportedVersions | Where-Object { $_.Major -eq 2 }

        if (-not $v2Versions) {
            throw "No REST API 2.x versions supported by this FlashBlade. Supported: $($supportedVersions -join ', ')"
        }

        $negotiatedVersion = $v2Versions[0].Version
    }

    # Authenticate based on method
    $authToken = $null
    $bearerToken = $null
    $tokenExpiresAt = $null
    $tokenTtlSeconds = $null

    if ($PSCmdlet.ParameterSetName -eq 'ApiToken') {
        # Direct API token login
        $authToken = Invoke-PfbApiTokenLogin -Endpoint $Endpoint -ApiToken $ApiToken -SkipCertificateCheck:$IgnoreCertificateError -TimeoutSec $timeoutSec
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Certificate') {
        # OAuth2 JWT certificate-based authentication
        $oauthLoginParams = @{
            Endpoint       = $Endpoint
            ClientId       = $ClientId
            Issuer         = $Issuer
            KeyId          = $KeyId
            Username       = $Username
            PrivateKeyFile = $PrivateKeyFile
        }
        if ($PrivateKeyPassword) {
            $oauthLoginParams['PrivateKeyPassword'] = $PrivateKeyPassword
        }
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
            $oauthLoginParams['SkipCertificateCheck'] = $true
        }

        $oauthResult = Invoke-PfbOAuth2Login @oauthLoginParams

        # The bearer token IS the auth token for REST API calls
        # It goes in the Authorization header, not x-auth-token
        $bearerToken = $oauthResult.AccessToken
        $authToken = $bearerToken
        $tokenExpiresAt = $oauthResult.ExpiresAt
        $tokenTtlSeconds = $oauthResult.TtlSeconds
        # Deliberately NOT "$ApiToken = $null" here: $ApiToken carries
        # [ValidateNotNullOrEmpty()] on its PSVariable, which re-validates on ANY
        # assignment regardless of which parameter set was actually bound -- so
        # assigning $null unconditionally throws even though this branch never
        # received -ApiToken. $ApiToken is already $null/unbound for the Certificate
        # parameter set; leaving it untouched fixes a live, already-shipped crash
        # (introduced v2.0.3, still in v2.0.5) in every real Certificate/OAuth2 login.
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Credential' -or $PSCmdlet.ParameterSetName -eq 'PSCredential') {
        $parsedVersions = ConvertTo-PfbVersionObject -Versions $supportedVersions
        $nativeLoginSupported = [bool]($parsedVersions | Where-Object { $_.Major -gt 2 -or ($_.Major -eq 2 -and $_.Minor -ge 26) })

        if ($nativeLoginSupported) {
            # Native REST 2.x username/password login — POST /api/login with JSON body.
            # /api/login is unversioned and is part of REST 2.x. No SSH required.
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
            try {
                # PtrToStringAuto is ANSI on non-Windows platforms, which truncates a UTF-16
                # BSTR at its first null byte (i.e. after the first character) -- silently
                # sending a mangled password to /api/login on Linux/macOS. PtrToStringBSTR
                # reads the BSTR by its length prefix and is correct (and UTF-16) on every
                # platform.
                $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                $loginBody = @{ username = $Username; password = $plainPassword } | ConvertTo-Json -Compress
            }
            finally {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) | Out-Null
                $plainPassword = $null
            }

            $loginParams = @{
                Method      = 'POST'
                Uri         = "https://${Endpoint}/api/login"
                Body        = $loginBody
                ContentType = 'application/json'
                TimeoutSec  = $timeoutSec
            }
            if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
                $loginParams['SkipCertificateCheck'] = $true
            }
            $loginBody = $null  # release the JSON body containing the password

            try {
                $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
            }
            catch {
                throw "Username/password authentication failed for FlashBlade '${Endpoint}': $(ConvertTo-PfbApiError -Method 'POST' -Endpoint 'login' -ErrorRecord $_)"
            }

            $authToken = $loginResponse.Headers['x-auth-token']
            if ($authToken -is [array]) { $authToken = $authToken[0] }

            # Try to retrieve (or mint) a long-lived API token for auto-reconnect.
            # Best-effort: succeeds for users with admin privileges; falls through silently otherwise.
            # Use a local variable since the $ApiToken parameter retains its [ValidateNotNullOrEmpty]
            # constraint and would reject a $null reassignment.
            $cachedApiToken  = $null
            $tokenHeaders    = @{ 'x-auth-token' = $authToken }
            $encodedName     = [System.Uri]::EscapeDataString($Username)
            $tokenBaseUri    = "https://${Endpoint}/api/${negotiatedVersion}/admins/api-tokens"
            $tokenInvokeArgs = @{}
            if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
                $tokenInvokeArgs['SkipCertificateCheck'] = $true
            }
            $tokenInvokeArgs['TimeoutSec'] = $timeoutSec
            # Pick the item whose admin matches our username. The /admins/api-tokens endpoint
            # silently ignores the names= / ids= filters and returns all admins, with the
            # caller's own token unmasked and other admins' tokens redacted to '****'. We must
            # filter client-side to avoid grabbing a peer admin's masked entry.
            $isOurAdmin = { param($item) $item.admin -and $item.admin.name -eq $Username }
            $isRealToken = { param($t) $t -and $t -ne '****' -and -not ($t -match '^\*+$') }

            try {
                $existing = Invoke-RestMethod -Uri "${tokenBaseUri}?expose_api_token=true" `
                                              -Headers $tokenHeaders -ErrorAction Stop @tokenInvokeArgs
                $mine = $existing.items | Where-Object { & $isOurAdmin $_ } | Select-Object -First 1
                if ($mine -and $mine.api_token -and (& $isRealToken $mine.api_token.token)) {
                    $cachedApiToken = $mine.api_token.token
                }
            }
            catch {
                Write-Verbose "Could not read existing API token for '$Username': $($_.Exception.Message)"
            }
            if (-not $cachedApiToken) {
                try {
                    $minted = Invoke-RestMethod -Uri "${tokenBaseUri}?names=${encodedName}" `
                                                -Method POST -Headers $tokenHeaders -ErrorAction Stop @tokenInvokeArgs
                    $mine = $minted.items | Where-Object { & $isOurAdmin $_ } | Select-Object -First 1
                    if ($mine -and $mine.api_token -and (& $isRealToken $mine.api_token.token)) {
                        $cachedApiToken = $mine.api_token.token
                    }
                }
                catch {
                    Write-Verbose "Could not mint API token for '$Username': $($_.Exception.Message)"
                }
            }
            if ($cachedApiToken) {
                $ApiToken = $cachedApiToken
            } else {
                Write-Verbose "Connected without a cached API token. Auto-reconnect on 401 will be unavailable for this session."
            }
        }
        else {
            # Native REST 2.x login isn't available on this array (< Purity//FB 4.8.1 /
            # REST API 2.26). FlashBlade has never had a way to exchange username/password
            # for a token over REST itself -- confirmed against real arrays and the
            # source of FlashBlade's original PowerShell module -- so SSH is the only
            # mechanism available to bootstrap from credentials to a token here.
            try {
                $mintedToken = Get-PfbApiTokenViaSsh -Endpoint $Endpoint -Username $Username -Password $Password -Verbose:$VerbosePreference
            }
            catch {
                throw "Username/password authentication failed for FlashBlade '${Endpoint}'. This array supports API versions: $($supportedVersions -join ', '). Native REST login requires API 2.26+ (Purity//FB 4.8.1+), which is not supported here; FlashBlade has no REST-based username/password login below that version, so this cmdlet falls back to SSH to mint an API token. The SSH fallback failed: $($_.Exception.Message)"
            }

            $ApiToken = $mintedToken
            $authToken = Invoke-PfbApiTokenLogin -Endpoint $Endpoint -ApiToken $ApiToken -SkipCertificateCheck:$IgnoreCertificateError -TimeoutSec $timeoutSec
        }
    }

    if ([string]::IsNullOrEmpty($authToken)) {
        throw "Authentication failed: No x-auth-token received from FlashBlade '${Endpoint}'."
    }

    # Capability-map coverage check: run ONCE here, unconditionally, so the result is
    # cached on the connection for its whole life rather than recomputed per call. Firing
    # at connect universally also means Phase 1's context cmdlets need no trigger of their
    # own. Deliberately no Gallery lookup -- this module runs against air-gapped arrays, so
    # point at the remedy rather than probing for it.
    # Get-PfbCapabilityMap returns $null for a MISSING file, but it does not guard
    # ConvertFrom-Json -- a corrupt or truncated shipped map THROWS. Today that surfaces at
    # request time inside Assert-PfbApiCapability; calling it here unguarded would newly
    # break Connect-PfbArray itself, so you could not even establish a connection to
    # diagnose it. A diagnostic warning must never be able to fail the connect path.
    $capabilityMap = $null
    try { $capabilityMap = Get-PfbCapabilityMap }
    catch { Write-Verbose "Connect-PfbArray: capability map could not be loaded for the coverage check: $($_.Exception.Message)" }

    # The helper hands back the highest scanned version it already computed, so this path
    # never re-parses generatedFrom. Recomputing here would place an unguarded copy of the
    # helper's own throwing expression OUTSIDE its try/catch -- safe only by an invariant
    # living in another file, which is exactly the kind of non-local coupling this phase is
    # removing. One parse, inside one guard.
    $highestScanned = $null
    $exceedsCapabilityMapCoverage = Test-PfbCapabilityMapCoverage -NegotiatedVersion $negotiatedVersion -CapabilityMap $capabilityMap -HighestScanned ([ref]$highestScanned)
    if ($exceedsCapabilityMapCoverage) {
        Write-Warning ("Connected array is running REST $negotiatedVersion; this module's " +
            "capability map only covers through REST $highestScanned -- capability checks " +
            'for anything newer, including context scoping, cannot be fully verified and ' +
            'may not error even if unsupported. Check the PowerShell Gallery for a newer ' +
            'release (Update-Module).')
    }

    # Build connection object — properties align with PureRestClientBase (Pfa2)
    $connection = [PSCustomObject]@{
        PSTypeName           = 'PureStorage.FlashBlade.Connection'
        # Pfa2-aligned properties
        HttpEndpoint         = "https://${Endpoint}"
        Username             = $Username
        ApiToken             = $ApiToken
        RestApiVersion       = $negotiatedVersion
        # Internal properties used by Invoke-PfbApiRequest / Disconnect-PfbArray
        Endpoint             = $Endpoint
        AuthToken            = $authToken
        ApiVersion           = $negotiatedVersion
        BearerToken          = $bearerToken
        AuthMethod           = $PSCmdlet.ParameterSetName
        SkipCertificateCheck = [bool]$IgnoreCertificateError
        HttpTimeoutMs        = $HttpTimeout
        ConnectedAt          = [datetime]::UtcNow
        # Diagnostic: array outruns the bundled capability map's scanned range. Deliberately
        # NOT in $defaultProps below -- diagnostic state, not default-display material.
        ExceedsCapabilityMapCoverage = $exceedsCapabilityMapCoverage
        # Certificate/OAuth2 refresh state — only populated when AuthMethod is 'Certificate'
        ClientId             = $ClientId
        Issuer               = $Issuer
        KeyId                = $KeyId
        PrivateKeyFile       = $PrivateKeyFile
        PrivateKeyPassword   = $PrivateKeyPassword
        TokenExpiresAt       = $tokenExpiresAt
        TokenTtlSeconds      = $tokenTtlSeconds
        # Fusion context state. $null means "unset"; an empty entry list means "explicitly no
        # context" -- two distinct states, so never test these with if ($x). DefaultContext is
        # durable for the session; ContextOverride is block-scoped (Invoke-PfbInContext).
        DefaultContext       = $null
        ContextOverride      = $null
        # Reserved: populated in a later phase. Declared here so every connection object has a
        # uniform shape.
        AdminLocality   = $null
    }

    # Hide secrets from default display. Sensitive fields (ApiToken, AuthToken,
    # BearerToken) are still accessible programmatically — Format-List * / direct
    # property access ($conn.ApiToken) work — but they no longer appear in the
    # default Format-List view that runs when a user just types $conn at the prompt.
    $defaultProps = @(
        'HttpEndpoint', 'Endpoint', 'Username', 'AuthMethod',
        'ApiVersion', 'RestApiVersion', 'SkipCertificateCheck', 'ConnectedAt'
    )
    $psStandardMembers = [System.Management.Automation.PSMemberInfo[]]@(
        [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]$defaultProps)
    )
    Add-Member -InputObject $connection -MemberType MemberSet -Name PSStandardMembers -Value $psStandardMembers

    # A context supplied at connect is the durable session default. Already validated above,
    # before authentication. The gate is $contextRequested -- never a truthiness or $null test
    # on $contextEntries, which is what keeps $null (unset) distinct from @() (explicit
    # no-context).
    #
    # DELIBERATELY BEFORE THE CACHE ASSIGNMENT BELOW. This block can throw (the gate), and the
    # caches used to be repointed above it -- so a rejected context left a connection this cmdlet
    # never returned installed as $script:PfbDefaultArray, with the offending context attached: a
    # "failed" connect that is nonetheless the default array. Validating first and installing
    # afterwards is what NARROWS that, and it is why the two were reordered rather than an
    # unwind-on-throw being bolted on.
    #
    # It narrows rather than eliminates, and the difference matters. Nothing between here and the
    # install READS the caches -- the resolver is passed $connection explicitly -- but the
    # reconnect and proactive-refresh paths inside Invoke-PfbApiRequest WRITE them
    # (Invoke-PfbApiRequest.ps1:147-152 and :266-271), and their guards are ENDPOINT-KEYED:
    # ContainsKey($Array.Endpoint) / PfbDefaultArray.Endpoint -eq. Those guards are false only when
    # the endpoint is not already cached, i.e. on a FIRST connect. On a re-connect to an endpoint
    # already in $script:PfbArrays -- routine -- a 401/403-then-success on the resolver's probe
    # fires those writes and repoints both caches at the object the resolver handed them, which
    # since the context strip is the resolver's PROBE COPY, not $connection. So a subsequent gate
    # throw still leaves the caches pointing at an object this cmdlet never returned. Narrow (needs
    # an already-cached endpoint plus a transient auth failure on the probe) and fail-safe in the
    # common case -- see the strip site in Resolve-PfbAdminLocality for why the probe copy
    # landing there is benign, and on what that depends. Closing it properly means capturing and
    # restoring both cache slots in a catch -- the very unwind the reordering was chosen to avoid --
    # so it is recorded here rather than fixed. Do not delete this paragraph believing the
    # reordering is airtight.
    if ($contextRequested) {
        # BOTH halves of the predicate, deliberately mirroring Invoke-PfbApiRequest's $hasContext
        # ($null -ne $resolvedContext -and @(...Entries).Count -gt 0). $contextRequested alone is
        # TRUE for -Context @(), which in this codebase is the first-class "explicitly no context"
        # state, NOT "a context is being set". Gating only on the flag made
        # `-Credential <local admin> -Context @()` pay a GET /admins probe and then hard-throw with
        # an empty value interpolated into the message ("the context '' would return..."), failing
        # a connect that asked for no context at all. Keep this recognisably the same predicate as
        # the request path's -- a different shape here is how the two drift apart.
        if (@($contextEntries).Count -gt 0) {
            # Resolved HERE, not unconditionally at connect: a session that never touches Fusion
            # must not pay for a GET /admins round trip (maintainer ruling 2026-08-05). The other
            # site is Set-PfbContext's end{}. Exactly two sites, both one-shot session setup --
            # which is why no cache is needed and AdminLocality stays two-state-plus-null
            # ('local'/'remote' known, $null indeterminate -> fail open). Do NOT add a per-call
            # site such as Invoke-PfbInContext: it mutates ContextOverride in place on the shared
            # connection and a thousand-iteration loop would mean a thousand probes. Do NOT
            # memoize, and do NOT introduce a third "not yet asked" state to make memoizing safe.
            #
            # Best-effort and non-fatal: see Resolve-PfbAdminLocality, which also documents
            # that this is inert for the DEFAULT -ApiToken set (no Username to look up), costs ~3
            # round trips rather than 1 on a management-access-policy 403, and strips the context
            # from its own probe so the identity question is never routed to another array.
            $connection.AdminLocality = Resolve-PfbAdminLocality -Array $connection

            # Closes what the Task 11 review parked as a gap: the connect-time context path is now
            # exactly where resolution happens, so it is also where the gate can rule.
            #
            # This is the cmdlet's first throw AFTER a successful login, so the session it just
            # minted would otherwise be abandoned with no logout -- a script retrying a rejected
            # -Context in a loop would fill the array's session log. Released best-effort here.
            # The original error is captured first and re-thrown explicitly so a failure inside the
            # logout can never replace or mask it.
            try {
                Assert-PfbContextAdminLocality -Array $connection -Context (New-PfbContext -Entries $contextEntries)
            }
            catch {
                $gateError = $_
                try {
                    # TimeoutSec matters MORE here than on a normal call: the caller is already
                    # waiting on an error, so an endpoint that accepts TCP and never answers would
                    # stall a cmdlet that has already decided to fail.
                    $logoutParams = @{
                        Method     = 'POST'
                        Uri        = "https://${Endpoint}/api/logout"
                        Headers    = @{ 'x-auth-token' = $authToken }
                        TimeoutSec = $timeoutSec
                    }
                    if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
                        $logoutParams['SkipCertificateCheck'] = $true
                    }
                    Invoke-RestMethod @logoutParams -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Verbose "Could not release the session minted for the rejected connect to '${Endpoint}': $($_.Exception.Message)"
                }
                # Deliberately NOT Disconnect-PfbArray: that also evicts $Endpoint from the module
                # caches, which on a re-connect would destroy the caller's still-valid PREVIOUS
                # connection to the same array as a side effect of this one being rejected.
                throw $gateError
            }
        }

        $connection.DefaultContext = New-PfbContext -Entries $contextEntries
    }

    # Cache the connection. Last, so only a fully validated connection is ever installed.
    $script:PfbDefaultArray = $connection
    $script:PfbArrays[$Endpoint] = $connection

    return $connection
}
