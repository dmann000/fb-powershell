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

Describe 'Local group member selector lift' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
    }

    It 'lifts group.name to GroupName without rebuilding the response' {
        $fixture = [PSCustomObject]@{
            name = 'member-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            group = [PSCustomObject]@{ name = 'group-1' }
        }
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

        $result = Get-PfbLocalGroupMember -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        $result.GroupName | Should -Be 'group-1'
        $result.group.name | Should -Be 'group-1'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'group', 'GroupName')
        $requests.Count | Should -Be 1
        $requests[0].Method | Should -Be 'GET'
        $requests[0].Endpoint | Should -Be 'directory-services/local/groups/members'
        @($requests[0].QueryParams.Keys) | Should -HaveCount 0
    }

    It 'pipes GroupName into Get-PfbLocalGroupMember as scalar group_names' {
        $fixture = [PSCustomObject]@{
            name = 'member-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            group = [PSCustomObject]@{ name = 'group-1' }
        }
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

        $first = Get-PfbLocalGroupMember -Array $script:fakeArray
        $second = $first | Get-PfbLocalGroupMember -Array $script:fakeArray
        $expectedGroupName = 'group-1'

        $requests.Count | Should -Be 2
        $requests[0].Method | Should -Be 'GET'
        $requests[0].Endpoint | Should -Be 'directory-services/local/groups/members'
        @($requests[0].QueryParams.Keys) | Should -HaveCount 0
        $requests[1].Method | Should -Be 'GET'
        $requests[1].Endpoint | Should -Be 'directory-services/local/groups/members'
        $requests[1].QueryParams['group_names'] | Should -Be $expectedGroupName
        $requests[1].QueryParams['group_names'] | Should -Not -Match '@\{'
        @($requests[1].QueryParams.Keys) | Should -Be @('group_names')
        $second | Should -Not -BeNullOrEmpty
    }

    # The selector parameter is GroupName, not Group: a parameter named Group is shadowed by the
    # response's own 'group' property during by-property-name binding (the property matching the
    # parameter NAME wins over any property matching an alias), so the lifted GroupName could never
    # bind and the whole item was stringified onto group_names instead. Group survives as an alias,
    # so -Group stays bindable -- which is the half of this case that must not regress.
    It 'declares Group and group_name as aliases of the GroupName selector parameter' {
        $command = Get-Command Get-PfbLocalGroupMember
        @($command.Parameters.Keys) | Should -Not -Contain 'Group'
        $command.Parameters['GroupName'].Aliases | Should -Contain 'group_name'
        $command.Parameters['GroupName'].Aliases | Should -Contain 'Group'
    }

    It 'still binds -Group on the command line after the rename' {
        $requests = [System.Collections.Generic.List[object]]::new()
        $global:PfbSelectorLiftRequests = $requests
        $global:PfbSelectorLiftFixture = $null

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            $global:PfbSelectorLiftRequests.Add([PSCustomObject]@{
                    Method = $Method
                    Endpoint = $Endpoint
                    QueryParams = $QueryParams
                })
            return $global:PfbSelectorLiftFixture
        }

        Get-PfbLocalGroupMember -Group 'group-1', 'group-2' -Array $script:fakeArray | Out-Null

        $requests.Count | Should -Be 1
        $requests[0].QueryParams['group_names'] | Should -Be 'group-1,group-2'
    }

    It 'does not add GroupName when group.name is null' {
        $fixture = [PSCustomObject]@{
            name = 'member-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            group = [PSCustomObject]@{ name = $null }
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $result = Get-PfbLocalGroupMember -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'group')
        @($result.PSObject.Properties.Name) | Should -Not -Contain 'GroupName'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }

    It 'does not add GroupName when group is absent' {
        $fixture = [PSCustomObject]@{
            name = 'member-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $result = Get-PfbLocalGroupMember -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker')
        @($result.PSObject.Properties.Name) | Should -Not -Contain 'GroupName'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }

    It 'does not overwrite an existing GroupName' {
        $fixture = [PSCustomObject]@{
            name = 'member-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            group = [PSCustomObject]@{ name = 'nested-group' }
            GroupName = 'existing-group'
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $result = Get-PfbLocalGroupMember -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        $result.GroupName | Should -Be 'existing-group'
        $result.group.name | Should -Be 'nested-group'
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'group', 'GroupName')
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }
}

Describe 'ObjectStore access policy role selector lift convergence' {
    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
    }

    It 'preserves the original association while lifting policy.name to PolicyName' {
        $fixture = [PSCustomObject]@{
            name = 'association-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            policy = [PSCustomObject]@{ name = 'policy-1' }
            member = [PSCustomObject]@{ name = 'member-1' }
        }
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

        $result = Get-PfbObjectStoreAccessPolicyRole -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        $result.PolicyName | Should -Be 'policy-1'
        $result.MemberName | Should -Be 'member-1'
        $result.policy.name | Should -Be 'policy-1'
        $result.member.name | Should -Be 'member-1'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'policy', 'member', 'PolicyName', 'MemberName')
        $requests.Count | Should -Be 1
        $requests[0].Method | Should -Be 'GET'
        $requests[0].Endpoint | Should -Be 'object-store-access-policies/object-store-roles'
        @($requests[0].QueryParams.Keys) | Should -HaveCount 0
    }

    It 'does not add PolicyName when policy.name is null' {
        $fixture = [PSCustomObject]@{
            name = 'association-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            policy = [PSCustomObject]@{ name = $null }
            member = [PSCustomObject]@{ name = 'member-1' }
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $result = Get-PfbObjectStoreAccessPolicyRole -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'policy', 'member', 'MemberName')
        @($result.PSObject.Properties.Name) | Should -Not -Contain 'PolicyName'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }

    It 'does not add PolicyName when policy is absent' {
        $fixture = [PSCustomObject]@{
            name = 'association-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            member = [PSCustomObject]@{ name = 'member-1' }
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $result = Get-PfbObjectStoreAccessPolicyRole -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'member', 'MemberName')
        @($result.PSObject.Properties.Name) | Should -Not -Contain 'PolicyName'
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }

    It 'does not overwrite an existing PolicyName' {
        $fixture = [PSCustomObject]@{
            name = 'association-1'
            context = [PSCustomObject]@{ name = 'array-a' }
            marker = 'preserve-me'
            policy = [PSCustomObject]@{ name = 'nested-policy' }
            member = [PSCustomObject]@{ name = 'member-1' }
            PolicyName = 'existing-policy'
        }
        $global:PfbSelectorLiftFixture = $fixture

        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest {
            return $global:PfbSelectorLiftFixture
        }

        $result = Get-PfbObjectStoreAccessPolicyRole -Array $script:fakeArray

        [object]::ReferenceEquals($result, $fixture) | Should -BeTrue
        $result.PolicyName | Should -Be 'existing-policy'
        $result.policy.name | Should -Be 'nested-policy'
        $result.MemberName | Should -Be 'member-1'
        @($result.PSObject.Properties.Name) | Should -Be @('name', 'context', 'marker', 'policy', 'member', 'PolicyName', 'MemberName')
        $result.context.name | Should -Be 'array-a'
        $result.marker | Should -Be 'preserve-me'
    }
}
