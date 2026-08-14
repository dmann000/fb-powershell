#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SYNOPSIS
    Guards the -TotalOnly switch against the published endpoint capabilities (issue #102).

.DESCRIPTION
    The FlashBlade REST spec declares total_only on a minority of GET collection
    endpoints. Before #102 the module exposed -TotalOnly on 26 cmdlets whose endpoints
    never declared it, so the switch silently no-opped on the wire.

    This guard enumerates every exported command that still exposes -TotalOnly, resolves
    its endpoint literal out of the function body, and requires the committed
    Data/PfbCapabilityMap.json to declare total_only for that endpoint. It deliberately
    has no skip path: it reads only committed data (never the gitignored tools/specs) and
    fails, rather than skipping, when its inputs are missing or empty.
#>

# Discovery-time data. Pester 5 builds -ForEach expansions during discovery, so these
# literals must live at the top level -- values assigned inside BeforeAll are not
# available when the tests are generated.
$removedTotalOnlyCmdlets = @(
    'Get-PfbFileLock', 'Get-PfbFileLockClient', 'Get-PfbFileSystemExport', 'Get-PfbFileSystemGroup',
    'Get-PfbFileSystemGroupQuota', 'Get-PfbFileSystemSession', 'Get-PfbFileSystemUser',
    'Get-PfbFileSystemUserGroupQuotaPolicy', 'Get-PfbFileSystemUserQuota', 'Get-PfbOpenFile',
    'Get-PfbObjectStoreAccessPolicy', 'Get-PfbObjectStoreAccessPolicyAction',
    'Get-PfbObjectStoreAccessPolicyRole', 'Get-PfbObjectStoreAccessPolicyRule',
    'Get-PfbObjectStoreAccessPolicyUser', 'Get-PfbObjectStoreRemoteCredential',
    'Get-PfbObjectStoreRole', 'Get-PfbObjectStoreRoleAccessPolicy', 'Get-PfbObjectStoreTrustPolicy',
    'Get-PfbObjectStoreTrustPolicyRule', 'Get-PfbObjectStoreUserAccessPolicy',
    'Get-PfbUserGroupQuotaPolicy', 'Get-PfbUserGroupQuotaPolicyFileSystem',
    'Get-PfbUserGroupQuotaPolicyMember', 'Get-PfbUserGroupQuotaPolicyRule', 'Get-PfbServer'
)

$supportedTotalOnlyCmdlets = @(
    'Get-PfbBucket', 'Get-PfbBucketPerformance', 'Get-PfbBucketS3Performance', 'Get-PfbFileSystem',
    'Get-PfbFileSystemGroupPerformance', 'Get-PfbFileSystemReplicaLinkTransfer',
    'Get-PfbFileSystemSnapshot', 'Get-PfbFileSystemSnapshotTransfer',
    'Get-PfbFileSystemStorageClass', 'Get-PfbFileSystemUserPerformance',
    'Get-PfbObjectStoreAccount', 'Get-PfbRealm'
)

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $manifest = Join-Path $repoRoot 'PureStorageFlashBladePowerShell.psd1'
    Import-Module $manifest -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.25'; AuthToken = 'x' }

    # Committed capability data only -- no tools/specs, no generation step, no skip path.
    # ConvertFrom-Json has no -Depth on Windows PowerShell 5.1; the map is far shallower
    # than 5.1's built-in limit, so none is needed.
    $script:mapPath = Join-Path $repoRoot 'Data/PfbCapabilityMap.json'
    $script:map = if (Test-Path -LiteralPath $script:mapPath) {
        Get-Content -LiteralPath $script:mapPath -Raw | ConvertFrom-Json
    }
    else {
        $null
    }

    # endpoint key ('GET /file-systems') -> does the spec declare total_only?
    $script:totalOnlySupport = @{}
    if ($null -ne $script:map) {
        $endpointsProperty = $script:map.PSObject.Properties['endpoints']
        if ($endpointsProperty -and $null -ne $endpointsProperty.Value) {
            foreach ($endpoint in $endpointsProperty.Value.PSObject.Properties) {
                $parameterNames = @()
                $parametersProperty = $endpoint.Value.PSObject.Properties['parameters']
                if ($parametersProperty -and $null -ne $parametersProperty.Value) {
                    $parameterNames = @($parametersProperty.Value.PSObject.Properties.Name)
                }

                $script:totalOnlySupport[$endpoint.Name] = ($parameterNames -contains 'total_only')
            }
        }
    }

    $script:endpointCount = $script:totalOnlySupport.Count

    # Every exported command that still exposes -TotalOnly, with the endpoint literals
    # its body passes to Invoke-PfbApiRequest.
    $script:exposers = @(
        foreach ($command in Get-Command -Module PureStorageFlashBladePowerShell -CommandType Function, Cmdlet) {
            if (-not $command.Parameters.ContainsKey('TotalOnly')) { continue }

            $text = if ($command.ScriptBlock) { $command.ScriptBlock.ToString() } else { '' }
            $endpoints = @(
                [regex]::Matches($text, '-Endpoint\s+([''"])([^''"]+)\1') |
                    ForEach-Object { $_.Groups[2].Value } |
                    Select-Object -Unique
            )

            [PSCustomObject]@{
                Name      = $command.Name
                Endpoints = $endpoints
            }
        }
    )

    $script:offenders = @(
        foreach ($exposer in $script:exposers) {
            if ($exposer.Endpoints.Count -eq 0) {
                "$($exposer.Name): exposes -TotalOnly but no -Endpoint literal could be resolved"
                continue
            }

            foreach ($endpoint in $exposer.Endpoints) {
                $key = "GET /$endpoint"
                if (-not $script:totalOnlySupport.ContainsKey($key)) {
                    "$($exposer.Name): '$key' is absent from the capability map"
                }
                elseif (-not $script:totalOnlySupport[$key]) {
                    "$($exposer.Name): '$key' does not declare total_only"
                }
            }
        }
    )
}

# The literal arrays above exist only in the discovery-phase scope, so a run-phase It body
# cannot see them. Passing them through -ForEach makes them run-phase variables without
# duplicating the lists.
Describe '-TotalOnly is exposed only where the published spec declares total_only (#102)' -ForEach @{
    supported = $supportedTotalOnlyCmdlets
} {

    It 'reads a usable committed capability map' {
        Test-Path $mapPath | Should -BeTrue
        $map | Should -Not -BeNullOrEmpty
        # PSMemberInfoCollection is not ICollection, so .Count on it yields the scalar 1 --
        # wrap in @() before counting.
        @($map.endpoints.PSObject.Properties).Count | Should -BeGreaterThan 500
        $endpointCount | Should -BeGreaterThan 500
    }

    It 'finds exactly the 12 cmdlets that legitimately expose -TotalOnly' {
        @($exposers).Count | Should -Be 12
        (@($exposers.Name) | Sort-Object) -join ',' |
            Should -Be ((@($supported) | Sort-Object) -join ',')
    }

    It 'resolves exactly one endpoint literal for every exposer' {
        @($exposers | Where-Object { $_.Endpoints.Count -ne 1 }).Count | Should -Be 0
    }

    It 'has no cmdlet exposing -TotalOnly on an endpoint that does not declare total_only' {
        @($offenders) | Should -BeNullOrEmpty
    }
}

Describe 'the 26 cmdlets corrected by #102 no longer expose -TotalOnly' {

    It 'exposes no TotalOnly parameter: <_>' -ForEach $removedTotalOnlyCmdlets {
        (Get-Command $_).Parameters.Keys | Should -Not -Contain 'TotalOnly'
    }

    It 'rejects -TotalOnly at bind time (FileSystem family)' {
        { Get-PfbFileSystemGroup -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }

    It 'rejects -TotalOnly at bind time (ObjectStore family)' {
        { Get-PfbObjectStoreAccessPolicy -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }

    It 'rejects -TotalOnly at bind time (Policy family)' {
        { Get-PfbUserGroupQuotaPolicy -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }

    It 'rejects -TotalOnly at bind time (Server family)' {
        { Get-PfbServer -TotalOnly -Array $fakeArray } |
            Should -Throw -ExpectedMessage '*TotalOnly*'
    }
}

Describe 'the 12 cmdlets whose endpoints do declare total_only keep the switch (#102 is not a blanket removal)' {

    It 'still exposes a TotalOnly switch: <_>' -ForEach $supportedTotalOnlyCmdlets {
        $command = Get-Command $_
        $command.Parameters.Keys | Should -Contain 'TotalOnly'
        $command.Parameters['TotalOnly'].ParameterType | Should -Be ([switch])
    }

    It 'has capability-map backing for the switch it keeps: <_>' -ForEach $supportedTotalOnlyCmdlets {
        $cmdletName = $_
        $exposer = @($exposers | Where-Object { $_.Name -eq $cmdletName })
        $exposer.Count | Should -Be 1
        $exposer = $exposer[0]
        $key = "GET /$($exposer.Endpoints[0])"
        $totalOnlySupport.ContainsKey($key) | Should -BeTrue
        $totalOnlySupport[$key] | Should -BeTrue
    }
}
