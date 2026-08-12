function New-PfbFileSystem {
    <#
    .SYNOPSIS
        Creates a new file system on the FlashBlade.
    .DESCRIPTION
        Creates a file system with the specified configuration. Typed parameters cover the
        common fields: size + hard-limit, NFS/SMB/HTTP enablement with associated export and
        share policies, multi-protocol access control, default user/group quotas, eradication
        mode, snapshot directory visibility, and source snapshot cloning.

        Note: when neither -Nfs nor -Smb nor -Http is passed, the file system is created
        with all protocols disabled. The FlashBlade may still expose internal NFS/SMB
        export records in a disabled state — this is API behavior, not a module bug. Only
        the protocol switches you pass are flipped to enabled.

        Default exports: this cmdlet always sends the API's default_exports query parameter,
        and sends the documented empty value when -DefaultExports is omitted, so no default
        NFS or SMB export to the default server is created unless you ask for one. Because
        default_exports was introduced in REST 2.16, every invocation of this cmdlet now
        requires an array running REST 2.16 or newer.

        SMB security note: enabling SMB without -SmbSharePolicy uses the FB's pre-defined
        full-access share policy. For production shares, pass -SmbSharePolicy with the
        name of a policy that grants the access you intend.
    .PARAMETER Name
        Name of the file system.
    .PARAMETER Provisioned
        Provisioned size in bytes. Omit (or pass 0) for unlimited.
    .PARAMETER HardLimit
        Enforce -Provisioned as a hard quota.
    .PARAMETER DefaultUserQuota
        Default per-user space quota in bytes.
    .PARAMETER DefaultGroupQuota
        Default per-group space quota in bytes.
    .PARAMETER Nfs
        Enable NFSv3 + NFSv4.1.
    .PARAMETER NfsV3
        Enable NFSv3 only (use instead of -Nfs for v3-only).
    .PARAMETER NfsV41
        Enable NFSv4.1 only.
    .PARAMETER NfsRules
        Inline NFS export rules string (deprecated by FB in favor of -NfsExportPolicy).
    .PARAMETER NfsExportPolicy
        Name of a pre-existing NFS Export Policy to attach.
    .PARAMETER Smb
        Enable SMB.
    .PARAMETER SmbSharePolicy
        Name of a pre-existing SMB Share Policy to attach. Without this, SMB defaults to
        full access — set this for any non-lab share.
    .PARAMETER SmbClientPolicy
        Name of a pre-existing SMB Client Policy to attach.
    .PARAMETER Http
        Enable HTTP.
    .PARAMETER MultiProtocolAccessControlStyle
        Required when both NFS and SMB are enabled. Valid: nfs, smb, shared, independent,
        mode-bits.
    .PARAMETER SafeguardAcls
        Prevents NFS clients from erasing a configured ACL when setting NFS mode bits.
        Only meaningful with multi-protocol.
    .PARAMETER SnapshotDirectoryEnabled
        Expose the hidden .snapshot directory inside the FS mount.
    .PARAMETER FastRemoveDirectoryEnabled
        Enable the fast-remove directory feature.
    .PARAMETER GroupOwnership
        Group ownership semantics for new files. Valid: creator, parent-directory.
    .PARAMETER EradicationMode
        File system eradication policy. Valid: permission-based, retention-based.
    .PARAMETER Writable
        Whether the file system is writable. Defaults to $true.
    .PARAMETER SourceSnapshot
        Source snapshot to clone the file system from.
    .PARAMETER QosPolicy
        Name of a QoS policy to attach.
    .PARAMETER DefaultExports
        Protocols for which the FlashBlade should create a default export with default
        access. Valid: nfs, smb. Omit it and no default exports are created — the cmdlet
        sends the API's explicit empty value rather than letting the array apply its own
        default of 'nfs,smb'.

        Per the published API rule, an explicit protocol policy always creates that
        protocol's default export regardless of this parameter: -NfsRules or
        -NfsExportPolicy always creates the NFS export, and -SmbSharePolicy or
        -SmbClientPolicy always creates the SMB export.

        Passing 'nfs' with no -NfsRules and no -NfsExportPolicy sets nfs.rules to
        "*(rw,no_root_squash)".

        Passing 'smb' requires a share policy: supply -SmbSharePolicy, or on the
        -Attributes path an smb.share_policy in the body you provide. Without one the
        cmdlet throws before issuing the request, because the array would otherwise
        attach its built-in full-access share policy to the default SMB export.
    .PARAMETER Attributes
        Full request body as a hashtable. Mutually exclusive with the typed parameters
        above — use only when the typed params don't expose a field you need.
        -DefaultExports still applies: it is a query parameter and never enters the body,
        so the hashtable you supply is passed through untouched.
    .PARAMETER Array
        FlashBlade connection. Defaults to the current Connect-PfbArray session.
    .EXAMPLE
        New-PfbFileSystem -Name "project-data" -Provisioned 1TB -HardLimit -Nfs -NfsExportPolicy "nfs-rw-eng"

        1 TB enforced quota, NFS enabled with a policy reference.
    .EXAMPLE
        New-PfbFileSystem -Name "share01" -Smb -SmbSharePolicy "smb-rw-cost-eng" -Provisioned 500GB
    .EXAMPLE
        New-PfbFileSystem -Name "shared-fs" -Nfs -Smb `
            -SmbSharePolicy "smb-readwrite" -NfsExportPolicy "nfs-rw" `
            -MultiProtocolAccessControlStyle shared -SafeguardAcls $true
    .EXAMPLE
        New-PfbFileSystem -Name "legacy-nfs" -Nfs -DefaultExports nfs

        Opt back in to the array's default NFS export. Without -DefaultExports, no default
        export is created.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Individual')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(ParameterSetName = 'Individual')]
        [int64]$Provisioned,

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$HardLimit,

        [Parameter(ParameterSetName = 'Individual')]
        [int64]$DefaultUserQuota,

        [Parameter(ParameterSetName = 'Individual')]
        [int64]$DefaultGroupQuota,

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$Nfs,

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$NfsV3,

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$NfsV41,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$NfsRules,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$NfsExportPolicy,

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$Smb,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$SmbSharePolicy,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$SmbClientPolicy,

        [Parameter(ParameterSetName = 'Individual')]
        [switch]$Http,

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('nfs', 'smb', 'shared', 'independent', 'mode-bits')]
        [string]$MultiProtocolAccessControlStyle,

        [Parameter(ParameterSetName = 'Individual')]
        [Nullable[bool]]$SafeguardAcls,

        [Parameter(ParameterSetName = 'Individual')]
        [Nullable[bool]]$SnapshotDirectoryEnabled,

        [Parameter(ParameterSetName = 'Individual')]
        [Nullable[bool]]$FastRemoveDirectoryEnabled,

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('creator', 'parent-directory')]
        [string]$GroupOwnership,

        [Parameter(ParameterSetName = 'Individual')]
        [ValidateSet('permission-based', 'retention-based')]
        [string]$EradicationMode,

        [Parameter(ParameterSetName = 'Individual')]
        [Nullable[bool]]$Writable,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$SourceSnapshot,

        [Parameter(ParameterSetName = 'Individual')]
        [string]$QosPolicy,

        [Parameter(Mandatory, ParameterSetName = 'Attributes')]
        [hashtable]$Attributes,

        # No ParameterSetName: this belongs to both 'Individual' and 'Attributes'.
        [Parameter()]
        [ValidateSet('nfs', 'smb')]
        [string[]]$DefaultExports,

        [Parameter()]
        [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        $body = $Attributes
    }
    else {
        $body = @{}
        if ($Provisioned -gt 0)              { $body['provisioned'] = $Provisioned }
        if ($HardLimit)                      { $body['hard_limit_enabled'] = $true }
        if ($PSBoundParameters.ContainsKey('DefaultUserQuota'))  { $body['default_user_quota']  = $DefaultUserQuota }
        if ($PSBoundParameters.ContainsKey('DefaultGroupQuota')) { $body['default_group_quota'] = $DefaultGroupQuota }
        if ($PSBoundParameters.ContainsKey('SnapshotDirectoryEnabled')) { $body['snapshot_directory_enabled'] = [bool]$SnapshotDirectoryEnabled }
        if ($PSBoundParameters.ContainsKey('FastRemoveDirectoryEnabled')) { $body['fast_remove_directory_enabled'] = [bool]$FastRemoveDirectoryEnabled }
        if ($GroupOwnership)                 { $body['group_ownership'] = $GroupOwnership }
        if ($PSBoundParameters.ContainsKey('Writable')) { $body['writable'] = [bool]$Writable }
        if ($SourceSnapshot)                 { $body['source'] = @{ name = $SourceSnapshot } }
        if ($QosPolicy)                      { $body['qos_policy'] = @{ name = $QosPolicy } }
        if ($EradicationMode)                { $body['eradication_config'] = @{ eradication_mode = $EradicationMode } }

        # NFS — note: local hashtable name avoids collision with [switch]$Nfs (PowerShell vars are case-insensitive)
        $nfsBody = @{}
        if ($Nfs -or $NfsV3)  { $nfsBody['v3_enabled'] = $true }
        if ($Nfs -or $NfsV41) { $nfsBody['v4_1_enabled'] = $true }
        if ($NfsExportPolicy -and $NfsRules) {
            throw "Pass only one of -NfsExportPolicy or -NfsRules; the FlashBlade API rejects both in the same request."
        }
        if ($NfsExportPolicy) { $nfsBody['export_policy'] = @{ name = $NfsExportPolicy } }
        elseif ($NfsRules)    { $nfsBody['rules'] = $NfsRules }
        if ($nfsBody.Count -gt 0) { $body['nfs'] = $nfsBody }

        # SMB — local name avoids collision with [switch]$Smb
        if ($Smb -or $SmbSharePolicy -or $SmbClientPolicy) {
            $smbBody = @{ enabled = $true }
            if ($SmbSharePolicy)  { $smbBody['share_policy']  = @{ name = $SmbSharePolicy } }
            if ($SmbClientPolicy) { $smbBody['client_policy'] = @{ name = $SmbClientPolicy } }
            $body['smb'] = $smbBody

            if (-not $SmbSharePolicy) {
                Write-Warning "SMB enabled without -SmbSharePolicy. The FlashBlade will attach its built-in full-access share policy. Pass -SmbSharePolicy with a named policy for production shares."
            }
        }

        # HTTP
        if ($Http) { $body['http'] = @{ enabled = $true } }

        # Multi-protocol
        $mp = @{}
        if ($MultiProtocolAccessControlStyle) { $mp['access_control_style'] = $MultiProtocolAccessControlStyle }
        if ($PSBoundParameters.ContainsKey('SafeguardAcls')) { $mp['safeguard_acls'] = [bool]$SafeguardAcls }
        if ($mp.Count -gt 0) { $body['multi_protocol'] = $mp }
        elseif (($Nfs -or $NfsV3 -or $NfsV41) -and $Smb) {
            Write-Warning "Both NFS and SMB enabled but -MultiProtocolAccessControlStyle not specified. FlashBlade will default to 'shared'. Pass -MultiProtocolAccessControlStyle explicitly for production file systems."
        }
    }

    $queryParams = @{ 'names' = $Name }

    # default_exports is a QUERY parameter only — it must never enter $body, including on the
    # -Attributes path, where the caller owns the body outright.
    #
    # The local is deliberately named differently from the parameter: a local whose name
    # matches a parameter IS that parameter in PowerShell (case-insensitive), so assigning to
    # $DefaultExports here would re-run its ValidateSet against '' and throw.
    #
    # The omitted case is a single-element array containing the empty string, not a bare empty
    # string: ConvertTo-PfbQueryString drops scalar empty strings but joins arrays with commas,
    # so @('') is what actually reaches the wire as `default_exports=` — the documented value
    # for "create no default exports". It is assigned in two statements rather than from an
    # if/else expression because an if/else yields pipeline output, where a single-element array
    # collapses back to its element — direct assignment of an array literal does not.
    $defaultExportsValue = @('')
    if ($PSBoundParameters.ContainsKey('DefaultExports')) {
        $defaultExportsValue = @($DefaultExports)
    }
    $queryParams['default_exports'] = $defaultExportsValue

    # Requesting a default SMB export without naming a share policy makes the array attach its
    # built-in full-access share policy. Reject that here, before any request is issued, so the
    # broad policy can never be attached implicitly.
    #
    # On the -Attributes path the body is caller-owned and must not be mutated or reshaped, so
    # this only inspects it. The nested smb value can be any shape the caller supplied: absent,
    # $null, a hashtable, another IDictionary, a ConvertFrom-Json PSCustomObject, or a scalar.
    # Each of those has to reach the same message rather than an indexing or property error.
    if ($defaultExportsValue -contains 'smb') {
        $smbSharePolicySupplied = $false
        if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
            $smbValue = $null
            if ($null -ne $Attributes) { $smbValue = $Attributes['smb'] }

            if ($smbValue -is [System.Collections.IDictionary]) {
                # Cast first: IDictionary's own indexer returns $null for a missing key on every
                # implementation, whereas a generic dictionary's typed indexer throws.
                $smbSharePolicySupplied = $null -ne ([System.Collections.IDictionary]$smbValue)['share_policy']
            }
            elseif ($null -ne $smbValue) {
                $smbSharePolicySupplied =
                    ($null -ne $smbValue.psobject.Properties['share_policy']) -and
                    ($null -ne $smbValue.share_policy)
            }
        }
        else {
            $smbSharePolicySupplied = [bool]$SmbSharePolicy
        }

        if (-not $smbSharePolicySupplied) {
            throw "-DefaultExports includes 'smb' but no SMB share policy was supplied. Pass -SmbSharePolicy or omit 'smb' from -DefaultExports."
        }
    }

    if ($PSCmdlet.ShouldProcess($Name, 'Create file system')) {
        Invoke-PfbApiRequest -Array $Array -Method POST -Endpoint 'file-systems' -Body $body -QueryParams $queryParams
    }
}
