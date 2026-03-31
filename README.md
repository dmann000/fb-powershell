# Pure Storage FlashBlade PowerShell Toolkit

PowerShell module for managing Pure Storage FlashBlade arrays via the REST API 2.x. Provides **496 cmdlets** covering all FlashBlade REST 2.x endpoints with a `Connect-PfbArray` experience that mirrors the FlashArray `PureStoragePowerShellSDK2` module.

## Requirements

- **PowerShell 5.1** or later (Windows PowerShell or PowerShell 7+)
- **Posh-SSH** (optional) — required only for username/password authentication on Purity//FB 4.x+ where REST 1.x login is unavailable

## Installation

### From source

```powershell
# Clone the repository
git clone https://github.com/dmann000/fb-powershell.git

# Copy the module folder to a PSModulePath location
Copy-Item -Recurse .\fb-powershell\PureStorageFlashBladePowerShell `
    "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PureStorageFlashBladePowerShell"

# Import
Import-Module PureStorageFlashBladePowerShell
```

### Manual install

Download the release and copy the `PureStorageFlashBladePowerShell` folder (containing `.psd1`, `.psm1`, and `LICENSE`) into any directory listed in `$env:PSModulePath`.

## Authentication

### API Token (recommended)

The simplest way to connect. Generate a token from the FlashBlade GUI (**Settings → Access → API Tokens**) or CLI (`pureadmin create --api-token`).

```powershell
$array = Connect-PfbArray -Endpoint 10.0.0.1 -ApiToken "T-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -IgnoreCertificateError
```

### Username and Password

Connect using a local FlashBlade username and password — the same way you'd log into the GUI:

```powershell
$password = ConvertTo-SecureString "MyPassword" -AsPlainText -Force
$array = Connect-PfbArray -Endpoint 10.0.0.1 -Username "pureuser" -Password $password -IgnoreCertificateError
```

**How it works under the hood:**

When you provide `-Username` and `-Password`, the module attempts authentication in this order:

1. **REST 1.x login** — Sends credentials to the legacy `/api/login` endpoint. This works on older Purity//FB versions that still expose REST 1.x. If successful, the module retrieves an API token and upgrades to a REST 2.x session.

2. **SSH fallback** — If REST 1.x is unavailable (common on Purity//FB 4.x+), the module automatically connects to the FlashBlade over SSH and runs `pureadmin list --api-token --expose` to retrieve an existing API token for the user. If no token exists, it creates one with `pureadmin create --api-token`. This mirrors the behavior of `Connect-Pfa2Array` from the FlashArray SDK.

The SSH fallback requires the **Posh-SSH** module. Install it once:

```powershell
Install-Module -Name Posh-SSH -Scope CurrentUser -Force
```

If Posh-SSH is not installed and REST 1.x login fails, the cmdlet will display clear instructions explaining your options.

### PSCredential

Same as username/password, but using a standard PowerShell credential object. Follows the same REST 1.x → SSH fallback flow described above.

```powershell
$cred = Get-Credential
$array = Connect-PfbArray -Endpoint 10.0.0.1 -Credential $cred -IgnoreCertificateError
```

You can also pre-cache credentials for reuse across multiple connections:

```powershell
Set-PfbCredential -Credential (Get-Credential)
$array = Connect-PfbArray -Endpoint 10.0.0.1 -Credential (Get-PfbCredential) -IgnoreCertificateError
```

### Certificate (OAuth2/JWT)

For automated/service-account workflows using certificate-based authentication:

```powershell
$array = Connect-PfbArray -Endpoint 10.0.0.1 -Username "pureuser" `
    -ClientId "9472190-f792-712e-a639-0839fa830922" `
    -Issuer "myapp" -KeyId "e50c1a8f-..." `
    -PrivateKeyFile "C:\keys\fb-private.pem" -IgnoreCertificateError
```

### The `-IgnoreCertificateError` flag

Most FlashBlade arrays use self-signed SSL certificates. Pass `-IgnoreCertificateError` to bypass certificate validation. This is standard for lab and on-prem environments.

## Usage

### Basic workflow

```powershell
# Connect to the array
$array = Connect-PfbArray -Endpoint 10.0.0.1 -ApiToken $token -IgnoreCertificateError

# All subsequent cmdlets use the connection automatically
Get-PfbArray                # Array name, model, Purity version
Get-PfbArraySpace           # Capacity and usage
Get-PfbHardware             # Blades, drives, chassis

# Disconnect when done
Disconnect-PfbArray
```

### Managing file systems

```powershell
# List all file systems
Get-PfbFileSystem

# Create a file system (1 TB provisioned)
New-PfbFileSystem -Name "project-data" -Attributes @{ provisioned = 1TB }

# Update properties
Update-PfbFileSystem -Name "project-data" -Attributes @{ provisioned = 2TB }

# Take a snapshot
New-PfbFileSystemSnapshot -SourceName "project-data" -Suffix "daily-backup"

# List snapshots
Get-PfbFileSystemSnapshot

# Clean up
Remove-PfbFileSystemSnapshot -Name "project-data.daily-backup"
Remove-PfbFileSystem -Name "project-data"
```

### Object store (S3)

```powershell
# List accounts, users, and buckets
Get-PfbObjectStoreAccount
Get-PfbObjectStoreUser
Get-PfbBucket

# Create a bucket
New-PfbBucket -Name "logs-bucket" -Attributes @{ account = "myaccount" }
```

### Filtering and pagination

```powershell
# Filter by name
Get-PfbFileSystem -Filter "name='project-data'"

# Pagination is automatic — all results are returned by default
Get-PfbFileSystemSnapshot   # Returns all snapshots, even if >1000
```

### Multiple arrays

```powershell
# Connect to two arrays
$fb1 = Connect-PfbArray -Endpoint 10.0.0.1 -ApiToken $token1 -IgnoreCertificateError
$fb2 = Connect-PfbArray -Endpoint 10.0.0.2 -ApiToken $token2 -IgnoreCertificateError

# Target a specific array with -Array
Get-PfbFileSystem -Array $fb1
Get-PfbFileSystem -Array $fb2
```

### WhatIf / Confirm support

All state-changing cmdlets (New, Update, Remove) support `-WhatIf` and `-Confirm`:

```powershell
# Preview what would happen without making changes
Remove-PfbFileSystem -Name "test-fs" -WhatIf

# Prompt for confirmation before each action
Remove-PfbFileSystem -Name "test-fs" -Confirm
```

## Cmdlet Overview

| Category | Verbs | Examples |
|---|---|---|
| **Array** | Get | `Get-PfbArray`, `Get-PfbArraySpace`, `Get-PfbArrayPerformance` |
| **File Systems** | Get, New, Update, Remove | `Get-PfbFileSystem`, `New-PfbFileSystem` |
| **Snapshots** | Get, New, Remove | `Get-PfbFileSystemSnapshot` |
| **Buckets** | Get, New, Update, Remove | `Get-PfbBucket`, `New-PfbBucket` |
| **Policies** | Get, New, Update, Remove | `Get-PfbPolicy`, `New-PfbPolicyMember` |
| **Network** | Get, New, Update, Remove | `Get-PfbSubnet`, `Get-PfbNetworkInterface` |
| **Hardware** | Get | `Get-PfbHardware`, `Get-PfbBlade` |
| **Admin** | Get, New, Update, Remove | `Get-PfbAdmin`, `Get-PfbAdminSetting` |
| **Replication** | Get, New, Update, Remove | `Get-PfbBucketReplicaLink`, `Get-PfbTarget` |
| **Certificates** | Get, New, Update, Remove | `Get-PfbCertificate`, `New-PfbCertificate` |
| **Support** | Get, New, Test, Update | `Get-PfbSupport`, `Test-PfbSupport` |

All cmdlets follow the `Verb-PfbNoun` naming convention. Run `Get-Command -Module PureStorageFlashBladePowerShell` for the full list.

## Connection Object

`Connect-PfbArray` returns a connection object with these properties (aligned with `PureStoragePowerShellSDK2`):

| Property | Description |
|---|---|
| `Endpoint` | Hostname or IP of the connected FlashBlade |
| `HttpEndpoint` | Full base URL (`https://endpoint`) |
| `Username` | Authenticated username |
| `ApiToken` | API token used for the session |
| `ApiVersion` | Negotiated REST API version (e.g., `2.12`) |
| `RestApiVersion` | Alias for `ApiVersion` (Pfa2 compat) |

## Getting Help

Every cmdlet has built-in help with examples:

```powershell
# Detailed help for a specific cmdlet
Get-Help Connect-PfbArray -Full
Get-Help New-PfbFileSystem -Examples

# List all available cmdlets
Get-Command -Module PureStorageFlashBladePowerShell

# List cmdlets for a specific area
Get-Command -Module PureStorageFlashBladePowerShell -Noun PfbFileSystem*
Get-Command -Module PureStorageFlashBladePowerShell -Noun PfbBucket*
```

## Testing Results

v2.0.0 was validated against a live FlashBlade S200R2 (Purity//FB 4.6.8, API 2.24) on Windows PowerShell 5.1.

| Test Area | Result |
|---|---|
| **Pester unit tests** | 1,062 passed, 0 failed |
| **Module loads and exports** | 496 cmdlets confirmed |
| **Help coverage** | 496/496 cmdlets have Synopsis |
| **ShouldProcess (WhatIf/Confirm)** | 283/283 mutation cmdlets verified |
| **Naming conventions** | 496/496 follow `Verb-PfbNoun` pattern, all approved verbs |
| **Parameter consistency** | All cmdlets have `-Array`, correct parameter sets |
| **Live API — read-only cmdlets** | 199/205 passed, 0 failed, 6 skipped (unconfigured features or model-specific) |
| **Live array — mutation lifecycle** | File system + snapshot create/update/delete ✅ |
| **Live array — Connect-PfbArray** | ApiToken, Username/Password, PSCredential, SSH fallback ✅ |
| **Build consistency** | Built `.psm1` exports identical 496 cmdlets |
| **Code quality** | No `Write-Host` in cmdlets, no hardcoded IPs |

## Compatibility

- **FlashBlade**: Purity//FB 3.x and later (REST API 2.x)
- **PowerShell**: 5.1, 7.0+ (Windows, Linux, macOS)
- **Tested on**: FlashBlade S200R2, Purity//FB 4.6.8, API version 2.24

## Migration from v1.x (PureFBModule)

This is a complete rewrite. Key changes:

- **Module name**: `PureStorageFlashBladePowerShell` (was `PureFBModule`)
- **API**: REST 2.x only (v1.x targeted REST 1.x)
- **Authentication**: Session-based via `Connect-PfbArray` / `Disconnect-PfbArray`
- **Cmdlet naming**: `Verb-PfbNoun` pattern with `Get`, `New`, `Update`, `Remove` verbs

## License

Apache License 2.0 — see [LICENSE](LICENSE).

