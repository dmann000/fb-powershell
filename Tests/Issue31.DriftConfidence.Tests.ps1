#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbCmdletParamTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbApiDriftTools.ps1')

    # The 56 cmdlets this issue converts. All were 'high' confidence before the change
    # and must remain 'high' after it -- see design spec constraint 7.
    $script:inScope = @(
        'New-PfbApiToken','Update-PfbAdmin','Update-PfbApiClient','Update-PfbManagementAccessPolicy',
        'Update-PfbOidcIdp','Update-PfbSaml2Idp','Update-PfbCertificate','New-PfbCertificateCertificateGroup',
        'Update-PfbBucketAuditFilter','Update-PfbActiveDirectory','Update-PfbDirectoryServiceRole',
        'Update-PfbFileSystemExport','Update-PfbRealmDefaults','Update-PfbHardware','Update-PfbHardwareConnector',
        'Update-PfbAsyncLog','Update-PfbLogTargetFileSystem','Update-PfbLogTargetObjectStore',
        'Update-PfbSnmpManager','Update-PfbSyslogServer','New-PfbLegalHoldEntity','Update-PfbKmip',
        'Update-PfbLag','Update-PfbLegalHold','Update-PfbLegalHoldEntity','Update-PfbLifecycleRule',
        'New-PfbNetworkInterfaceTlsPolicy','Update-PfbDns','Update-PfbNetworkInterface',
        'Update-PfbNetworkInterfaceConnector','Update-PfbSubnet','New-PfbNodeGroupNode','Update-PfbNode',
        'Update-PfbNodeGroup','Update-PfbObjectStoreAccountExport','Update-PfbObjectStoreRemoteCredential',
        'Update-PfbObjectStoreRole','Update-PfbObjectStoreVirtualHost','New-PfbNetworkAccessRule',
        'New-PfbNfsExportRule','New-PfbPolicyFileSystemReplicaLink','New-PfbQosPolicyMember',
        'New-PfbS3ExportRule','New-PfbSmbClientRule','New-PfbSmbShareRule','Update-PfbQosPolicy',
        'Update-PfbSshCaPolicy','Update-PfbStorageClassTieringPolicy','Update-PfbTlsPolicy',
        'Update-PfbWormPolicy','New-PfbArrayConnection','New-PfbFileSystemReplicaLinkPolicy',
        'New-PfbFleetMember','Update-PfbArrayConnection','Update-PfbFleet','Update-PfbTarget'
    )
}

Describe 'Issue #31 - in-scope cmdlets keep high drift confidence' {
    It 'no in-scope write endpoint has dropped to partial confidence' {
        # Build-PfbApiDriftReport.ps1 has no -PassThru (verified: its parameters are
        # SpecsDirectory, PublicDirectory, PrivateDirectory, CapabilityMapPath,
        # FieldCmdletMapPath, OutputPath, ReportPath, SinceVersion). Generate to a temp
        # path so the run never mutates the committed Reports/ artifacts, then read it.
        $tmpJson = Join-Path ([IO.Path]::GetTempPath()) "pfb-drift-$([guid]::NewGuid()).json"
        $tmpMd   = [IO.Path]::ChangeExtension($tmpJson, '.md')
        & (Join-Path $repoRoot 'tools/Build-PfbApiDriftReport.ps1') -OutputPath $tmpJson -ReportPath $tmpMd | Out-Null
        $report = Get-Content $tmpJson -Raw | ConvertFrom-Json
        Remove-Item $tmpJson, $tmpMd -ErrorAction SilentlyContinue

        $regressed = @(
            $report.parameterGaps |
                Where-Object { $_.endpoint -match '^(POST|PATCH|PUT) ' } |
                Where-Object { $_.confidence.level -eq 'partial' } |
                Where-Object { @($_.cmdlets | Where-Object { $inScope -contains $_ }).Count -gt 0 } |
                ForEach-Object { "$($_.endpoint) [$($_.confidence.escapeHatchOnly -join ',')]" }
        )

        $regressed | Should -BeNullOrEmpty -Because @'
these endpoints became parser-untraceable, which means the drift report can no
longer see real gaps on them. Fix the body assignment so the parameter is BARE
and assigned INLINE, in one of the shapes Global Constraint 7 names. Do NOT
compute into a local variable first -- that is the pre-inversion rule and it
causes exactly the blindness this guard exists to catch.
'@
    }
}
