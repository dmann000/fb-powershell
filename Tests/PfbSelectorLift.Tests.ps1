#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Import-Module "$PSScriptRoot/../PureStorageFlashBladePowerShell.psd1" -Force
    $script:fakeArray = [PSCustomObject]@{
        Endpoint  = 'fb.example.test'
        ApiVersion = '2.0'
        AuthToken = 'x'
    }
}

$policyRows = @(
    @{
        Cmdlet = 'Get-PfbNetworkAccessRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 'network-access-policies/rules'
        InitialArgs = @{}
    }
    @{
        Cmdlet = 'Get-PfbNfsExportRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 'nfs-export-policies/rules'
        InitialArgs = @{}
    }
    @{
        Cmdlet = 'Get-PfbObjectStoreAccessPolicyRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 'object-store-access-policies/rules'
        InitialArgs = @{}
    }
    @{
        Cmdlet = 'Get-PfbObjectStoreTrustPolicyRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 'object-store-roles/object-store-trust-policies/rules'
        InitialArgs = @{ PolicyName = 'seed-policy' }
    }
    @{
        Cmdlet = 'Get-PfbS3ExportRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 's3-export-policies/rules'
        InitialArgs = @{ PolicyName = 'seed-policy' }
    }
    @{
        Cmdlet = 'Get-PfbSmbClientRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 'smb-client-policies/rules'
        InitialArgs = @{}
    }
    @{
        Cmdlet = 'Get-PfbSmbShareRule'
        LiftProperty = 'PolicyName'
        NestedProperty = 'policy'
        WireKey = 'policy_names'
        Alias = 'policy_name'
        Endpoint = 'smb-share-policies/rules'
        InitialArgs = @{}
    }
)

$roleRows = @(
    @{
        Cmdlet = 'Get-PfbObjectStoreTrustPolicy'
        LiftProperty = 'RoleName'
        NestedProperty = 'role'
        WireKey = 'role_names'
        Alias = 'role_name'
        Endpoint = 'object-store-roles/object-store-trust-policies'
        InitialArgs = @{ RoleName = 'seed-role' }
    }
)

Describe 'Policy and role selector lifts' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
    }

    It 'lifts <NestedProperty>.name to <LiftProperty> without rebuilding the response' -ForEach @($policyRows + $roleRows) {
        $fixture = [PSCustomObject]@{
            name = 'rule-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
        }
        $nestedName = if ($NestedProperty -eq 'role') { 'role-1' } else { 'policy-1' }
        $nested = [PSCustomObject]@{ name = $nestedName }
        $fixture | Add-Member -MemberType NoteProperty -Name $NestedProperty -Value $nested
        $requests = [System.Collections.Generic.List[object]]::new()
        $global:PfbSelectorLiftFixture = $fixture
        $global:PfbSelectorLiftRequests = $requests

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            $global:PfbSelectorLiftRequests.Add([PSCustomObject]@{
                    Method = $Method
                    Endpoint = $Endpoint
                    QueryParams = $QueryParams
                })
            return $global:PfbSelectorLiftFixture
        }

        $invokeArgs = @{} + $InitialArgs
        $invokeArgs['Array'] = $script:fakeArray
        $result = & $Cmdlet @invokeArgs
        $expectedName = if ($NestedProperty -eq 'role') { 'role-1' } else { 'policy-1' }

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        $result.$LiftProperty | Should -Be $expectedName
        $result.name | Should -Be 'rule-1'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
        $result.$NestedProperty.name | Should -Be $expectedName
        # Exactly one property added: the four fixture properties plus the lift, and nothing else.
        # Without this a rebuilt-or-over-decorated object could still satisfy every assertion above.
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', $NestedProperty, $LiftProperty)
        $requests.Count | Should -Be 1
        $requests[0].Endpoint | Should -Be $Endpoint
    }

    It 'pipes the lifted <LiftProperty> into <Cmdlet> as scalar <WireKey>' -ForEach @($policyRows + $roleRows) {
        $fixture = [PSCustomObject]@{
            name = 'rule-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
        }
        $nestedName = if ($NestedProperty -eq 'role') { 'role-1' } else { 'policy-1' }
        $nested = [PSCustomObject]@{ name = $nestedName }
        $fixture | Add-Member -MemberType NoteProperty -Name $NestedProperty -Value $nested
        $requests = [System.Collections.Generic.List[object]]::new()
        $global:PfbSelectorLiftFixture = $fixture
        $global:PfbSelectorLiftRequests = $requests

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            $global:PfbSelectorLiftRequests.Add([PSCustomObject]@{
                    Method = $Method
                    Endpoint = $Endpoint
                    QueryParams = $QueryParams
                })
            return $global:PfbSelectorLiftFixture
        }

        $invokeArgs = @{} + $InitialArgs
        $invokeArgs['Array'] = $script:fakeArray
        $first = & $Cmdlet @invokeArgs
        $second = $first | & $Cmdlet -Array $script:fakeArray

        $requests.Count | Should -Be 2
        $expectedName = if ($NestedProperty -eq 'role') { 'role-1' } else { 'policy-1' }
        $requests[1].Method | Should -Be 'GET'
        $requests[1].Endpoint | Should -Be $Endpoint
        $requests[1].QueryParams[$WireKey] | Should -Be $expectedName
        $requests[1].QueryParams[$WireKey] | Should -Not -Match '@\{'
        # The piped call binds nothing but the selector, so the selector must be the ONLY key on
        # the wire. An exact key set is what catches a stray or duplicate selector.
        @($requests[1].QueryParams.Keys) | Should -Be @($WireKey)
        $second | Should -Not -BeNullOrEmpty
    }

    It 'declares the wire alias <Alias> on <LiftProperty>' -ForEach @($policyRows + $roleRows) {
        $command = Get-Command $Cmdlet
        $command.Parameters[$LiftProperty].Aliases | Should -Contain $Alias
    }

    # Both halves of "add only when the nested object AND its name are non-null" need a case: a
    # guard that only checks .name blows up or mis-adds when the parent object itself is missing,
    # which is exactly what an older REST version or a sparse response gives you.
    It 'does not add <LiftProperty> when <NestedProperty> is <NestedState>' -ForEach @(
        @{
            Cmdlet = 'Get-PfbNetworkAccessRule'
            LiftProperty = 'PolicyName'
            NestedProperty = 'policy'
            NestedState = 'present with a null name'
            OmitNested = $false
            InitialArgs = @{}
        }
        @{
            Cmdlet = 'Get-PfbObjectStoreTrustPolicy'
            LiftProperty = 'RoleName'
            NestedProperty = 'role'
            NestedState = 'present with a null name'
            OmitNested = $false
            InitialArgs = @{ RoleName = 'seed-role' }
        }
        @{
            Cmdlet = 'Get-PfbNetworkAccessRule'
            LiftProperty = 'PolicyName'
            NestedProperty = 'policy'
            NestedState = 'absent entirely'
            OmitNested = $true
            InitialArgs = @{}
        }
        @{
            Cmdlet = 'Get-PfbObjectStoreTrustPolicy'
            LiftProperty = 'RoleName'
            NestedProperty = 'role'
            NestedState = 'absent entirely'
            OmitNested = $true
            InitialArgs = @{ RoleName = 'seed-role' }
        }
    ) {
        $fixture = [PSCustomObject]@{
            name = 'rule-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
        }
        if (-not $OmitNested) {
            $nested = [PSCustomObject]@{ name = $null }
            $fixture | Add-Member -MemberType NoteProperty -Name $NestedProperty -Value $nested
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $invokeArgs = @{} + $InitialArgs
        $invokeArgs['Array'] = $script:fakeArray
        $result = & $Cmdlet @invokeArgs

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        @($result.PSObject.Properties.Name) | Should -Not -Contain $LiftProperty
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }

    It 'does not overwrite an existing <LiftProperty>' -ForEach @(
        @{
            Cmdlet = 'Get-PfbNetworkAccessRule'
            LiftProperty = 'PolicyName'
            NestedProperty = 'policy'
            InitialArgs = @{}
        }
        @{
            Cmdlet = 'Get-PfbObjectStoreTrustPolicy'
            LiftProperty = 'RoleName'
            NestedProperty = 'role'
            InitialArgs = @{ RoleName = 'seed-role' }
        }
    ) {
        $fixture = [PSCustomObject]@{
            name = 'rule-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
        }
        $nested = [PSCustomObject]@{ name = 'nested-name' }
        $fixture | Add-Member -MemberType NoteProperty -Name $NestedProperty -Value $nested
        $fixture | Add-Member -MemberType NoteProperty -Name $LiftProperty -Value 'existing-name'
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $invokeArgs = @{} + $InitialArgs
        $invokeArgs['Array'] = $script:fakeArray
        $result = & $Cmdlet @invokeArgs

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        $result.$LiftProperty | Should -Be 'existing-name'
        $result.$NestedProperty.name | Should -Be 'nested-name'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }
}
