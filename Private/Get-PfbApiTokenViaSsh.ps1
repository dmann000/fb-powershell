function Get-PfbApiTokenViaSsh {
    <#
    .SYNOPSIS
        Retrieves or creates an API token from a FlashBlade via SSH (optional).
    .DESCRIPTION
        Internal helper that uses the Posh-SSH module to connect to a FlashBlade
        via SSH and retrieve an API token using the 'pureadmin' CLI.

        This provides functionality similar to Connect-Pfa2Array's ability to
        generate an API token from a username and password.

        OPTIONAL DEPENDENCY: Requires the Posh-SSH module (Install-Module Posh-SSH).
        If Posh-SSH is not installed, this function will throw an informative error.

        The function tries the following approaches in order:
        1. pureadmin list --api-token --expose  (retrieve existing token)
        2. pureadmin create --api-token          (generate a new token if none exists)
    .PARAMETER Endpoint
        The hostname or IP address of the FlashBlade.
    .PARAMETER Username
        The SSH username (typically 'pureuser' or an AD/LDAP admin account).
    .PARAMETER Password
        The password as a SecureString.
    .PARAMETER AcceptKey
        Automatically accept the SSH host key. Default: $true for lab environments.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$Endpoint,
        [Parameter(Mandatory)] [string]$Username,
        [Parameter(Mandatory)] [System.Security.SecureString]$Password,
        [Parameter()] [bool]$AcceptKey = $true
    )

    # Check if Posh-SSH is available
    if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
        throw @"
The Posh-SSH module is required for SSH-based API token generation but is not installed.
This is an OPTIONAL feature that enables Connect-PfbArray to generate an API token
from a username and password via SSH, similar to Connect-Pfa2Array on FlashArray.

To install Posh-SSH, run:
  Install-Module -Name Posh-SSH -Scope CurrentUser -Force

After installing, retry your Connect-PfbArray command with -Username and -Password.

Alternative authentication methods that do not require Posh-SSH:
  1. Use -ApiToken (generate via FlashBlade GUI or CLI: pureadmin create --api-token)
  2. Use OAuth2 certificate auth: -ClientId -Issuer -KeyId -PrivateKeyFile -Username
"@
    }

    # Import Posh-SSH if not already loaded
    Import-Module Posh-SSH -ErrorAction Stop

    # Build PSCredential for SSH
    $sshCredential = New-Object System.Management.Automation.PSCredential($Username, $Password)

    # Establish SSH session
    $session = $null
    try {
        $sshParams = @{
            ComputerName = $Endpoint
            Credential   = $sshCredential
            ErrorAction  = 'Stop'
        }
        if ($AcceptKey) {
            $sshParams['AcceptKey'] = $true
        }
        $session = New-SSHSession @sshParams
    }
    catch {
        throw "SSH connection to FlashBlade '${Endpoint}' failed: $($_.Exception.Message)"
    }

    $sessionId = $session.SessionId
    $apiToken = $null

    try {
        # Approach 1: Try to list existing API token
        Write-Verbose "Attempting to retrieve existing API token via SSH..."
        $listResult = Invoke-SSHCommand -SessionId $sessionId -Command "pureadmin list --api-token --expose" -ErrorAction Stop

        if ($listResult.ExitStatus -eq 0 -and $listResult.Output) {
            # Parse the output - typically tabular: Name  API Token  Created  Expires
            # The token is a long string like T-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
            $tokenLine = $listResult.Output | Where-Object { $_ -match 'T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' }
            if ($tokenLine) {
                if ($tokenLine -match '(T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                    $apiToken = $Matches[1]
                    Write-Verbose "Retrieved existing API token via SSH."
                }
            }
        }

        # Approach 2: If no existing token, create one
        if (-not $apiToken) {
            Write-Verbose "No existing API token found. Creating a new one via SSH..."
            $createResult = Invoke-SSHCommand -SessionId $sessionId -Command "pureadmin create --api-token" -ErrorAction Stop

            if ($createResult.ExitStatus -eq 0 -and $createResult.Output) {
                $tokenLine = $createResult.Output | Where-Object { $_ -match 'T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' }
                if ($tokenLine) {
                    if ($tokenLine -match '(T-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                        $apiToken = $Matches[1]
                        Write-Verbose "Created new API token via SSH."
                    }
                }
            }

            # If create also failed, report the error output
            if (-not $apiToken -and $createResult.Error) {
                $errMsg = $createResult.Error -join "`n"
                throw "Failed to create API token via SSH: $errMsg"
            }
        }
    }
    finally {
        # Always clean up the SSH session
        if ($session) {
            Remove-SSHSession -SessionId $sessionId -ErrorAction SilentlyContinue | Out-Null
        }
    }

    if (-not $apiToken) {
        throw "Could not retrieve or create an API token via SSH on FlashBlade '${Endpoint}'. Verify the user '${Username}' has admin privileges."
    }

    return $apiToken
}

