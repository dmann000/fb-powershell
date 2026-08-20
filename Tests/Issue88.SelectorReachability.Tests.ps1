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

# Parameters that are not selectors: paging/shaping options and request-body fields. Listed
# literally so the completeness check below can prove that every *other* published parameter
# on the 18 cmdlets is classified exactly once by the tables.
$nonSelectorParams = @(
    'Array', 'Filter', 'Sort', 'Limit', 'TotalOnly'      # common query and shaping options
    'StartTime', 'EndTime', 'Resolution', 'Type'         # performance-window options
    'RemoteDefaultExports', 'CancelInProgressTransfers'  # replica-link body/behaviour flags
    'ManagementAddress', 'ReplicationAddresses', 'CaCertificateGroup'
    'Encrypted', 'Remote', 'Throttle', 'Attributes'      # array-connection body fields
)

# The explicit composite exceptions. Each entry names the companion parameters that make
# the selector usable, and how the incomplete form is refused:
#   Refusal = 'Guard'     -> the cmdlet's own guard throws the given message and issues zero
#                            requests.
#   Refusal = 'Binder'    -> PowerShell's parameter binder refuses the call before the cmdlet
#                            body runs. Asserted on the ErrorId, because the engine's message
#                            text is localizable and version-dependent.
#   Refusal = 'Mandatory' -> parameter binding demands the companion. Such a form is NEVER
#                            invoked here: an unbound mandatory parameter makes an interactive
#                            host prompt, which would hang the run. Asserted on metadata.
$compositeExceptions = @(
    # Fail-closed removals: a policy alone or a member alone is never enough to delete.
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'PolicyName'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A replica link member must be identified: supply -MemberId*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'PolicyId'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A replica link member must be identified: supply -MemberId*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'MemberId'; With = @{ PolicyName = 'p1' }; Refusal = 'Guard'; Message = '*A policy must be identified: supply -PolicyName or -PolicyId.*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'RemoteName'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A policy must be identified: supply -PolicyName or -PolicyId.*' }
    @{ Cmdlet = 'Remove-PfbFileSystemReplicaLinkPolicy'; Selector = 'RemoteId'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A policy must be identified: supply -PolicyName or -PolicyId.*' }

    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'PolicyName'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A replica link member must be identified: supply -MemberId*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'PolicyId'; With = @{ MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A replica link member must be identified: supply -MemberId*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'MemberId'; With = @{ PolicyName = 'p1' }; Refusal = 'Guard'; Message = '*A policy must be identified: supply -PolicyName or -PolicyId.*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'RemoteName'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A policy must be identified: supply -PolicyName or -PolicyId.*' }
    @{ Cmdlet = 'Remove-PfbPolicyFileSystemReplicaLink'; Selector = 'RemoteId'; With = @{ PolicyName = 'p1'; MemberId = 'm1' }; Refusal = 'Guard'; Message = '*A policy must be identified: supply -PolicyName or -PolicyId.*' }

    # A remote qualifier narrows a transfer cancellation; it never identifies one on its own.
    # Neither -Name nor -Id is bound in that form, so no parameter set resolves and the
    # binder - not a cmdlet guard - refuses the call.
    @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer'; Selector = 'RemoteName'; With = @{ Name = 'fs1.suffix' }; Refusal = 'Binder'; ErrorId = 'AmbiguousParameterSet' }
    @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer'; Selector = 'RemoteId'; With = @{ Id = 't1' }; Refusal = 'Binder'; ErrorId = 'AmbiguousParameterSet' }

    # A replica link is identified by local file system plus remote, so both halves are mandatory.
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'LocalFileSystemName'; With = @{ RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'RemoteArrayName'; With = @{ LocalFileSystemName = 'fs1' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'RemoteId'; With = @{ LocalFileSystemName = 'fs1' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'RemoteFileSystemName'; With = @{ LocalFileSystemName = 'fs1'; RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }
    @{ Cmdlet = 'New-PfbFileSystemReplicaLink'; Selector = 'Id'; With = @{ LocalFileSystemName = 'fs1'; RemoteArrayName = 'FB-B' }; Refusal = 'Mandatory' }

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
        ErrorId     = $(if ($row.ContainsKey('ErrorId')) { $row.ErrorId } else { '' })
        Destructive = ($row.Cmdlet -notlike 'Get-*')
    }
}

$guardedCompositeCases = @($compositeCases | Where-Object { $_.Refusal -eq 'Guard' })
$binderCompositeCases = @($compositeCases | Where-Object { $_.Refusal -eq 'Binder' })
$mandatoryCompositeCases = @($compositeCases | Where-Object { $_.Refusal -eq 'Mandatory' })

# Every parameter published by an in-scope cmdlet is either a declared non-selector or is
# classified by exactly one table row. Built at discovery from the literal tables; compared
# against Get-Command at run time.
$classificationCases = foreach ($name in $issue88Cmdlets) {
    $selectors = @(
        foreach ($row in $standaloneTable) { if ($row.Cmdlet -eq $name) { $row.Selectors } }
        foreach ($row in $compositeExceptions) { if ($row.Cmdlet -eq $name) { $row.Selector } }
    )

    @{
        Cmdlet       = $name
        Classified   = @($selectors | Sort-Object -Unique)
        Duplicates   = @($selectors | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
        NonSelectors = $nonSelectorParams
    }
}

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
    . (Join-Path $PSScriptRoot 'PfbTestModule.ps1')
    $null = Import-PfbTestModule

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

    It '<Cmdlet> classifies every published selector exactly once' -ForEach $classificationCases {
        $published = @((Get-Command $Cmdlet).Parameters.Keys |
                Where-Object {
                    $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters -and
                    $_ -notin [System.Management.Automation.PSCmdlet]::OptionalCommonParameters -and
                    $_ -notin $NonSelectors
                } | Sort-Object)

        # A parameter that is neither a declared non-selector nor a table row is an
        # unclassified selector: reachability for it was never asserted.
        $published | Should -Be $Classified

        $Duplicates | Should -BeNullOrEmpty -Because 'a selector may hold only one classification'
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

Describe 'Issue 88 - binder composite exceptions are refused by parameter binding' {

    BeforeEach {
        Mock -ModuleName PureStorageFlashBladePowerShell Assert-PfbConnection { }
        Mock -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest { }
    }

    # Asserted on the ErrorId rather than the message: the binder's text is localizable and
    # has changed wording between PowerShell versions, but AmbiguousParameterSet is stable.
    It '<Cmdlet> -<Selector> alone is refused by the binder with no request' -ForEach $binderCompositeCases {
        $splat = @{ Array = $script:fakeArray }
        $splat[$Selector] = 'v1'
        if ($Destructive) { $splat['Confirm'] = $false }

        $caught = $null
        try { & $Cmdlet @splat -ErrorAction Stop } catch { $caught = $_ }

        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception | Should -BeOfType [System.Management.Automation.ParameterBindingException]
        $caught.FullyQualifiedErrorId | Should -BeLike "$ErrorId,*"

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 0 -Exactly
    }

    It '<Cmdlet> -<Selector> issues exactly one request once its documented companions are supplied' -ForEach $binderCompositeCases {
        $splat = @{ Array = $script:fakeArray }
        $splat[$Selector] = 'v1'
        foreach ($k in $With.Keys) { $splat[$k] = $With[$k] }
        if ($Destructive) { $splat['Confirm'] = $false }

        { & $Cmdlet @splat -ErrorAction Stop } | Should -Not -Throw

        Should -Invoke -ModuleName PureStorageFlashBladePowerShell Invoke-PfbApiRequest -Times 1 -Exactly
    }

    It '<Cmdlet> -<Selector> is declared in every parameter set, which is why no set resolves alone' -ForEach $binderCompositeCases {
        $cmd = Get-Command $Cmdlet
        $setsWithSelector = @($cmd.ParameterSets | Where-Object { $_.Parameters.Name -contains $Selector })
        $setsWithSelector.Count | Should -Be $cmd.ParameterSets.Count

        foreach ($set in $setsWithSelector) {
            @($set.Parameters | Where-Object { $_.IsMandatory -and $_.Name -ne $Selector }) |
                Should -Not -BeNullOrEmpty -Because "set '$($set.Name)' would otherwise resolve on -$Selector alone"
        }
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

    # Without this, the table's declared companions are decorative: any hashtable that merely
    # makes the call succeed would pass. Each declared companion must be the mandatory
    # parameter that actually forces the composite, in a set that carries the selector.
    It '<Cmdlet> -<Selector> declares companions that are mandatory in a set carrying the selector' -ForEach $mandatoryCompositeCases {
        $sets = @((Get-Command $Cmdlet).ParameterSets |
                Where-Object { $_.Parameters.Name -contains $Selector })

        foreach ($companion in $With.Keys) {
            $mandatoryIn = @($sets | Where-Object {
                    $_.Parameters | Where-Object { $_.Name -eq $companion -and $_.IsMandatory }
                })
            $mandatoryIn | Should -Not -BeNullOrEmpty -Because "-$companion is listed as a companion of -$Selector but is mandatory in no set that carries it"
        }

        # And the companions together must satisfy at least one whole set, so the documented
        # composite form is genuinely complete rather than accidentally sufficient.
        $satisfied = @($sets | Where-Object {
                $unmet = @($_.Parameters |
                        Where-Object { $_.IsMandatory -and $_.Name -ne $Selector -and $_.Name -notin $With.Keys })
                $unmet.Count -eq 0
            })
        $satisfied | Should -Not -BeNullOrEmpty -Because "the declared companions of -$Selector satisfy no complete parameter set"
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
