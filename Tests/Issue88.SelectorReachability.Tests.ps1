#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
    Issue #88 - replication/policy selector reachability.

    Every documented selector on the 18 cmdlets in the issue scope must be reachable on
    its own, so a user can filter by any one of them without discovering that the cmdlet
    silently requires a companion parameter. The exceptions are enumerated literally
    below: a selector only gets to require a companion if that requirement is spelled out
    here and pinned by its own test.

    The tables are literal and evaluated at discovery time on purpose. Deriving them from
    the module (Get-Command, the capability map, ...) would make the suite agree with
    whatever the code currently does, which is exactly the property under test.
#>

# ---------------------------------------------------------------------------
# Discovery-time literal tables
# ---------------------------------------------------------------------------

$issue88Cmdlets = @(
    'Get-PfbArrayConnectionPath'
    'Get-PfbArrayConnectionPerformanceReplication'
    'Get-PfbArrayConnection'
    'Remove-PfbArrayConnection'
    'Get-PfbBucketReplicaLink'
    'Get-PfbFileSystemReplicaLink'
    'Get-PfbFileSystemReplicaLinkPolicy'
    'Remove-PfbFileSystemReplicaLinkPolicy'
    'Get-PfbFileSystemReplicaLinkTransfer'
    'New-PfbFileSystemReplicaLink'
    'Remove-PfbFileSystemReplicaLink'
    'Remove-PfbFileSystemSnapshotTransfer'
    'Get-PfbPolicyAllMember'
    'Get-PfbPolicyFileSystemReplicaLink'
    'Remove-PfbPolicyFileSystemReplicaLink'
    'Update-PfbArrayConnection'
    'New-PfbFileSystemReplicaLinkPolicy'
    'New-PfbPolicyFileSystemReplicaLink'
)

# Selectors that must bind with no companion parameter at all.
$standaloneTable = @(
    @{ Cmdlet = 'Get-PfbArrayConnectionPath'; Selectors = @('RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'Get-PfbArrayConnectionPerformanceReplication'; Selectors = @('RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'Get-PfbArrayConnection'; Selectors = @('RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'Remove-PfbArrayConnection'; Selectors = @('RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'Get-PfbBucketReplicaLink'; Selectors = @('LocalBucketName', 'RemoteBucketName', 'RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'Get-PfbFileSystemReplicaLink'; Selectors = @('LocalFileSystemName', 'RemoteFileSystemName', 'RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'Get-PfbFileSystemReplicaLinkPolicy'; Selectors = @('PolicyName', 'PolicyId', 'MemberId', 'RemoteName', 'RemoteId') }
    @{ Cmdlet = 'Get-PfbFileSystemReplicaLinkTransfer'; Selectors = @('NameOrOwnerName', 'Id', 'RemoteName', 'RemoteId') }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLink'; Selectors = @('Id') }
    @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer'; Selectors = @('Name', 'Id') }
    @{ Cmdlet = 'Get-PfbPolicyAllMember'; Selectors = @('PolicyName', 'PolicyId', 'MemberName', 'MemberId', 'MemberType', 'RemoteName', 'RemoteId') }
    @{ Cmdlet = 'Get-PfbPolicyFileSystemReplicaLink'; Selectors = @('PolicyName', 'PolicyId', 'MemberId', 'RemoteName', 'RemoteId') }
    @{ Cmdlet = 'Update-PfbArrayConnection'; Selectors = @('RemoteName', 'RemoteId', 'Id') }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLinkPolicy'; Selectors = @('PolicyName', 'PolicyId', 'MemberId', 'LocalFileSystemName', 'LocalFileSystemId', 'RemoteName', 'RemoteId') }
    @{ Cmdlet = 'New-PfbPolicyFileSystemReplicaLink'; Selectors = @('PolicyName', 'PolicyId', 'MemberId', 'LocalFileSystemName', 'LocalFileSystemId', 'RemoteName', 'RemoteId') }
)

# The explicit composite exceptions. Each entry names the companion parameters that make
# the selector usable, and how the incomplete form is refused:
#   Refusal = 'Guard'     -> the cmdlet throws the given message and issues zero requests
#   Refusal = 'Mandatory' -> parameter binding itself demands the companion. Such a form is
#                            NEVER invoked here: an unbound mandatory parameter makes an
#                            interactive host prompt, which would hang the run.
$compositeExceptions = @(
    # Fail-closed removals: a policy alone or a member alone is never enough to delete.
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'PolicyName'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-MemberId*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'PolicyId'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-MemberId*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'MemberId'; With = @{ PolicyName = 'p1' }; Refusal = 'Guard'; Message = '*-PolicyName or -PolicyId*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'RemoteName'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-PolicyName or -PolicyId*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'RemoteId'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-PolicyName or -PolicyId*' }

    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'PolicyName'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-MemberId*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'PolicyId'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-MemberId*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'MemberId'; With = @{ PolicyName = 'p1' }; Refusal = 'Guard'; Message = '*-PolicyName or -PolicyId*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'RemoteName'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-PolicyName or -PolicyId*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'RemoteId'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*-PolicyName or -PolicyId*' }

    # A remote qualifier narrows a transfer cancellation; it never identifies one on its own.
    @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer'; Selector = 'RemoteName'; With = @{ Name = 'fs1.suffix' }; Refusal = 'Guard'; Message = '*Parameter set cannot be resolved*' }
    @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer'; Selector = 'RemoteId'; With = @{ Id = 't1' }; Refusal = 'Guard'; Message = '*Parameter set cannot be resolved*' }

    # A replica link is identified by local file system plus remote, so both halves are mandatory.
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'LocalFileSystemName'; With = @{ RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'RemoteArrayName'; With = @{ LocalFileSystemName = 'fs1' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'RemoteId'; With = @{ LocalFileSystemName = 'fs1' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'RemoteFileSystemName'; With = @{ LocalFileSystemName = 'fs1'; RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }

    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLink'; Selector = 'LocalFileSystemName'; With = @{ RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLink'; Selector = 'RemoteArrayName'; With = @{ LocalFileSystemName = 'fs1' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLink'; Selector = 'RemoteId'; With = @{ LocalFileSystemName = 'fs1' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLink'; Selector = 'RemoteFileSystemName'; With = @{ LocalFileSystemName = 'fs1'; RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }
)

# Endpoints that declare no generic `ids` query parameter, so no Id (or Name) may appear.
$noGenericIdsCmdlets = @(
    @{ Cmdlet = 'Get-PfbFileSystemReplicaLinkPolicy' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy' }
    @{ Cmdlet = 'Get-PfbPolicyAllMember' }
    @{ Cmdlet = 'Get-PfbPolicyFileSystemReplicaLink' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLinkPolicy' }
    @{ Cmdlet = 'New-PfbPolicyFileSystemReplicaLink' }
)

# Flatten to per-case rows so a single failing selector names itself in the test output.
$standaloneCases = foreach ($row in $standaloneTable) {
    foreach ($selector in $row.Selectors) {
        @{
            Cmdlet      = $row.Cmdlet
            Selector    = $selector
            Destructive = ($row.Cmdlet -notlike 'Get-*')
        }
    }
}

$compositeCases = foreach ($row in $compositeExceptions) {
    @{
        Cmdlet      = $row.Cmdlet
        Selector    = $row.Selector
        With        = $row.With
        Refusal     = $row.Refusal
        Message     = $(if ($row.ContainsKey('Message')) { $row.Message } else { '' })
        Destructive = ($row.Cmdlet -notlike 'Get-*')
    }
}

$guardedCompositeCases = @($compositeCases | Where-Object { $_.Refusal -eq 'Guard' })
$mandatoryCompositeCases = @($compositeCases | Where-Object { $_.Refusal -eq 'Mandatory' })

# Pester 5 does not carry script-level discovery variables into the run phase, so the
# whole-table assertions travel as -ForEach data.
$tableCoverageCase = @(
    @{
        Expected = @($issue88Cmdlets | Sort-Object -Unique)
        Covered  = @(@($standaloneTable.Cmdlet) + @($compositeExceptions.Cmdlet) | Sort-Object -Unique)
        Clashes  = @(
            foreach ($row in $standaloneTable) {
                foreach ($selector in $row.Selectors) {
                    if ($compositeExceptions | Where-Object { $_.Cmdlet -eq $row.Cmdlet -and $_.Selector -eq $selector }) {
                        "$($row.Cmdlet) -$selector"
                    }
                }
            }
        )
    }
)

# ---------------------------------------------------------------------------

BeforeAll {
    $moduleRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $moduleRoot 'PureStorageFlashBladePowerShell.psd1') -Force

    $script:fakeArray = [PSCustomObject]@{ Endpoint = 'fb.example.test'; ApiVersion = '2.0'; AuthToken = 'x' }
}

Describe 'Issue 88 - the reachability table covers the whole issue scope' {

    It 'names exactly the 18 cmdlets in scope' -ForEach $tableCoverageCase {
        $Expected.Count | Should -Be 18
        $Covered | Should -Be $Expected
    }

    It 'lists no selector as both standalone and a composite exception' -ForEach $tableCoverageCase {
        $Clashes | Should -BeNullOrEmpty
    }

    It 'exports <_> from the module' -ForEach $issue88Cmdlets {
        (Get-Command -Module PureStorageFlashBladePowerShell -Name $_ -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'Issue 88 - documented selectors bind alone' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It '<Cmdlet> -<Selector> binds with no companion and issues exactly one request' -ForEach $standaloneCases {
        $splat = @{ Array = $script:fakeArray }
        $splat[$Selector] = 'v1'
        if ($Destructive) { $splat['Confirm'] = $false }

        { & $Cmdlet @splat -ErrorAction Stop } | Should -Not -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
    }

    It '<Cmdlet> publishes -<Selector>' -ForEach $standaloneCases {
        (Get-Command $Cmdlet).Parameters.Keys | Should -Contain $Selector
    }
}

Describe 'Issue 88 - composite exceptions are refused by a guard, not by a request' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    It '<Cmdlet> -<Selector> alone is refused before any request reaches the array' -ForEach $guardedCompositeCases {
        $splat = @{ Array = $script:fakeArray }
        $splat[$Selector] = 'v1'
        if ($Destructive) { $splat['Confirm'] = $false }

        { & $Cmdlet @splat -ErrorAction Stop } | Should -Throw $Message

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It '<Cmdlet> -<Selector> issues exactly one request once its documented companions are supplied' -ForEach $guardedCompositeCases {
        $splat = @{ Array = $script:fakeArray }
        $splat[$Selector] = 'v1'
        foreach ($k in $With.Keys) { $splat[$k] = $With[$k] }
        if ($Destructive) { $splat['Confirm'] = $false }

        { & $Cmdlet @splat -ErrorAction Stop } | Should -Not -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
    }
}

Describe 'Issue 88 - mandatory composite exceptions are declared, not discovered at runtime' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    # The incomplete form is deliberately never invoked: PowerShell would prompt for the
    # unbound mandatory parameter and hang a non-interactive run. Assert the requirement
    # from the parameter metadata instead.
    It '<Cmdlet> -<Selector> sits in no parameter set that lacks another mandatory parameter' -ForEach $mandatoryCompositeCases {
        $sets = @((Get-Command $Cmdlet).ParameterSets |
                Where-Object { $_.Parameters.Name -contains $Selector })
        $sets | Should -Not -BeNullOrEmpty

        foreach ($set in $sets) {
            $otherMandatory = @($set.Parameters |
                    Where-Object { $_.IsMandatory -and $_.Name -ne $Selector })
            $otherMandatory | Should -Not -BeNullOrEmpty -Because "set '$($set.Name)' would let -$Selector stand alone"
        }
    }

    It '<Cmdlet> -<Selector> issues exactly one request once its documented companions are supplied' -ForEach $mandatoryCompositeCases {
        $splat = @{ Array = $script:fakeArray }
        $splat[$Selector] = 'v1'
        foreach ($k in $With.Keys) { $splat[$k] = $With[$k] }
        if ($Destructive) { $splat['Confirm'] = $false }

        { & $Cmdlet @splat -ErrorAction Stop } | Should -Not -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
    }
}

Describe 'Issue 88 - endpoints that declare no generic ids publish no Id or Name' {

    It '<Cmdlet> publishes no Id parameter' -ForEach $noGenericIdsCmdlets {
        (Get-Command $Cmdlet).Parameters.Keys | Should -Not -Contain 'Id'
    }

    It '<Cmdlet> publishes no Name parameter' -ForEach $noGenericIdsCmdlets {
        (Get-Command $Cmdlet).Parameters.Keys | Should -Not -Contain 'Name'
    }

    It '<Cmdlet> hides no Id or Name alias on another parameter' -ForEach $noGenericIdsCmdlets {
        $aliases = (Get-Command $Cmdlet).Parameters.Values | ForEach-Object { $_.Aliases }
        $aliases | Should -Not -Contain 'Id'
        $aliases | Should -Not -Contain 'Name'
    }
}

Describe 'Issue 88 - the four corrected membership cmdlets carry no member_names surface' {

    It '<Cmdlet> publishes no MemberName parameter or alias' -ForEach @(
        @{ Cmdlet = 'Get-PfbFileSystemReplicaLinkPolicy' }
        @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy' }
        @{ Cmdlet = 'Get-PfbPolicyFileSystemReplicaLink' }
        @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink' }
    ) {
        (Get-Command $Cmdlet).Parameters.Keys | Should -Not -Contain 'MemberName'

        $aliases = (Get-Command $Cmdlet).Parameters.Values | ForEach-Object { $_.Aliases }
        $aliases | Should -Not -Contain 'MemberName'
    }

    It 'Get-PfbPolicyAllMember keeps MemberName, because policies-all/members does declare member_names' {
        (Get-Command Get-PfbPolicyAllMember).Parameters.Keys | Should -Contain 'MemberName'
    }

    It '<Cmdlet> keeps MemberName only as an alias of -LocalFileSystemName' -ForEach @(
        @{ Cmdlet = 'New-PfbFileSystemReplicaLinkPolicy' }
        @{ Cmdlet = 'New-PfbPolicyFileSystemReplicaLink' }
    ) {
        (Get-Command $Cmdlet).Parameters.Keys | Should -Not -Contain 'MemberName'
        (Get-Command $Cmdlet).Parameters['LocalFileSystemName'].Aliases | Should -Contain 'MemberName'
    }
}
