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
        When using -Password or -Credential, the cmdlet attempts authentication
        in the following order:
          1. REST API 1.x login (native username/password endpoint)
          2. SSH fallback via Posh-SSH (OPTIONAL — retrieves or creates an API token
             using the 'pureadmin' CLI over SSH, similar to Connect-Pfa2Array)

        The SSH fallback requires the optional Posh-SSH module: Install-Module Posh-SSH
        If Posh-SSH is not installed and REST 1.x login fails, the cmdlet will display
        instructions for installing Posh-SSH or using alternative authentication methods.

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
    .EXAMPLE
        $array = Connect-PfbArray -Endpoint fb01.example.com -ApiToken $token -IgnoreCertificateError

        Connect using an API token with SSL bypass for lab environments.
    .EXAMPLE
        $pw = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
        $array = Connect-PfbArray -Endpoint fb01.example.com -Username "pureuser" -Password $pw -IgnoreCertificateError

        Connect using username and password. If REST 1.x login is unavailable, falls back
        to SSH via Posh-SSH (optional) to retrieve an API token, similar to Connect-Pfa2Array.
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
        [int]$HttpTimeout = 30000
    )

    # Handle SSL bypass
    if ($IgnoreCertificateError) {
        Set-PfbCertificatePolicy
    }

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
        Method = 'GET'
        Uri    = $versionUri
    }
    if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
        $versionParams['SkipCertificateCheck'] = $true
    }

    try {
        $versionResponse = Invoke-RestMethod @versionParams -ErrorAction Stop
    }
    catch {
        throw "Failed to connect to FlashBlade at '${Endpoint}': $($_.Exception.Message)"
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
        $v2Versions = $supportedVersions | Where-Object { $_ -match '^2\.' } | ForEach-Object {
            $parts = $_ -split '\.'
            [PSCustomObject]@{
                Version = $_
                Major   = [int]$parts[0]
                Minor   = [int]$parts[1]
            }
        } | Sort-Object Major, Minor -Descending

        if (-not $v2Versions) {
            throw "No REST API 2.x versions supported by this FlashBlade. Supported: $($supportedVersions -join ', ')"
        }

        $negotiatedVersion = $v2Versions[0].Version
    }

    # Authenticate based on method
    $authToken = $null
    $bearerToken = $null

    if ($PSCmdlet.ParameterSetName -eq 'ApiToken') {
        # Direct API token login
        $loginUri = "https://${Endpoint}/api/login"
        $loginHeaders = @{ 'api-token' = $ApiToken }
        $loginParams = @{
            Method  = 'POST'
            Uri     = $loginUri
            Headers = $loginHeaders
        }
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
            $loginParams['SkipCertificateCheck'] = $true
        }

        try {
            $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
        }
        catch {
            throw "Authentication failed for FlashBlade '${Endpoint}': $($_.Exception.Message)"
        }

        $authToken = $loginResponse.Headers['x-auth-token']
        if ($authToken -is [array]) { $authToken = $authToken[0] }
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Certificate') {
        # OAuth2 JWT certificate-based authentication
        # Step 1: Generate a signed JWT
        $jwtParams = @{
            KeyId       = $KeyId
            ClientId    = $ClientId
            Issuer      = $Issuer
            Username    = $Username
            PrivateKeyFile = $PrivateKeyFile
        }
        if ($PrivateKeyPassword) {
            $jwtParams['PrivateKeyPassword'] = $PrivateKeyPassword
        }

        try {
            $jwt = New-PfbJwtToken @jwtParams
        }
        catch {
            throw "Failed to generate JWT for OAuth2 authentication: $($_.Exception.Message)"
        }

        # Step 2: Exchange JWT for OAuth2 access token
        $oauthBody = "grant_type=urn:ietf:params:oauth:grant-type:token-exchange&subject_token=${jwt}&subject_token_type=urn:ietf:params:oauth:token-type:jwt"
        $oauthParams = @{
            Method      = 'POST'
            Uri         = "https://${Endpoint}/oauth2/1.0/token"
            Body        = $oauthBody
            ContentType = 'application/x-www-form-urlencoded'
        }
        if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
            $oauthParams['SkipCertificateCheck'] = $true
        }

        try {
            $oauthResponse = Invoke-RestMethod @oauthParams -ErrorAction Stop
        }
        catch {
            throw "OAuth2 token exchange failed for FlashBlade '${Endpoint}': $($_.Exception.Message)"
        }

        $bearerToken = $oauthResponse.access_token
        if ([string]::IsNullOrEmpty($bearerToken)) {
            throw "OAuth2 token exchange returned no access_token from FlashBlade '${Endpoint}'."
        }

        # The bearer token IS the auth token for REST API calls
        # It goes in the Authorization header, not x-auth-token
        $authToken = $bearerToken
        $ApiToken = $null  # No API token in Certificate flow
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Credential' -or $PSCmdlet.ParameterSetName -eq 'PSCredential') {
        # Username/Password login via 1.x API
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        )

        $loginBody = @{
            username = $Username
            password = $plainPassword
        } | ConvertTo-Json -Compress

        # Try 1.x API login (supports username/password)
        $loginSuccess = $false
        foreach ($v1ver in @('1.12', '1.11', '1.10', '1.9', '1.8')) {
            $loginUri = "https://${Endpoint}/api/${v1ver}/login"
            $loginParams = @{
                Method      = 'POST'
                Uri         = $loginUri
                Body        = $loginBody
                ContentType = 'application/json'
            }
            if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
                $loginParams['SkipCertificateCheck'] = $true
            }

            try {
                $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
                $authToken = $loginResponse.Headers['x-auth-token']
                if ($authToken -is [array]) { $authToken = $authToken[0] }

                # Generate API token for auto-reconnect
                try {
                    $tokenResponse = Invoke-RestMethod -Uri "https://${Endpoint}/api/${v1ver}/api_token" -Method POST -Headers @{ 'x-auth-token' = $authToken } -ErrorAction Stop
                    $ApiToken = $tokenResponse.api_token
                }
                catch {
                    Write-Warning "Connected but could not generate API token for auto-reconnect: $($_.Exception.Message)"
                    $ApiToken = $null
                }

                $loginSuccess = $true
                break
            }
            catch {
                continue
            }
        }

        # Clear plaintext password
        $plainPassword = $null

        # If REST 1.x login failed, try SSH fallback (requires optional Posh-SSH module)
        if (-not $loginSuccess) {
            Write-Verbose "REST 1.x login failed. Attempting SSH fallback for API token generation..."
            try {
                $sshApiToken = Get-PfbApiTokenViaSsh -Endpoint $Endpoint -Username $Username -Password $Password -Verbose:$VerbosePreference
                $ApiToken = $sshApiToken
                Write-Verbose "API token obtained via SSH (Posh-SSH)."

                # Now login to REST 2.0 with the retrieved API token
                $loginUri = "https://${Endpoint}/api/login"
                $loginHeaders = @{ 'api-token' = $ApiToken }
                $loginParams = @{
                    Method  = 'POST'
                    Uri     = $loginUri
                    Headers = $loginHeaders
                }
                if ($IgnoreCertificateError -and $PSVersionTable.PSVersion.Major -ge 6) {
                    $loginParams['SkipCertificateCheck'] = $true
                }

                $loginResponse = Invoke-WebRequest @loginParams -UseBasicParsing -ErrorAction Stop
                $authToken = $loginResponse.Headers['x-auth-token']
                if ($authToken -is [array]) { $authToken = $authToken[0] }
                $loginSuccess = $true
            }
            catch {
                # SSH also failed — provide comprehensive error with alternatives
                throw @"
Username/password authentication failed for FlashBlade '${Endpoint}'.
Both REST 1.x login and SSH fallback were unsuccessful.

SSH error: $($_.Exception.Message)

To enable SSH-based authentication (similar to Connect-Pfa2Array):
  Install-Module -Name Posh-SSH -Scope CurrentUser -Force

Alternative authentication methods:
  1. Use -ApiToken (generate via FlashBlade GUI or CLI: pureadmin create --api-token)
  2. Use OAuth2 certificate auth: -ClientId -Issuer -KeyId -PrivateKeyFile -Username
"@
            }
        }
    }

    if ([string]::IsNullOrEmpty($authToken)) {
        throw "Authentication failed: No x-auth-token received from FlashBlade '${Endpoint}'."
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
    }

    # Cache the connection
    $script:PfbDefaultArray = $connection
    $script:PfbArrays[$Endpoint] = $connection

    return $connection
}
