#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbPipelineSelectorTools.ps1 -- the analysis layer of the
    issue #90 pipeline-selector audit.
.DESCRIPTION
    Fixtures shared by more than one Describe live in the FILE-level BeforeAll below.
    A Describe's own BeforeAll is not reliably visible to another Describe across the
    Pester/StrictMode combinations this repo gates on.

    tools/lib/PfbPipelineSelectorTools.ps1 is #Requires -Version 7.0, so every Describe here
    carries the same -Skip guard the other tools/ tests use -- and the file-level BeforeAll
    guards its own body too, because a skipped Describe does not stop a file-level BeforeAll
    from running and dot-sourcing a 7-only script on 5.1 kills the whole container.
#>

BeforeAll {
    $script:isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
    $script:repoRoot = Split-Path -Parent $PSScriptRoot

    if ($script:isPwsh7) {
        . (Join-Path $script:repoRoot 'tools/lib/PfbPipelineSelectorTools.ps1')
        . (Join-Path $script:repoRoot 'tools/lib/PfbCmdletParamTools.ps1')

        $script:module = Import-Module (Join-Path $script:repoRoot 'PureStorageFlashBladePowerShell.psd1') -Force -PassThru
        $script:bound = Get-PfbPipelineBoundParameter -Module $script:module

        $script:shapeMap = Get-Content (Join-Path $script:repoRoot 'Data/PfbResponseShapeMap.json') -Raw |
            ConvertFrom-Json
        $script:producerIndex = Get-PfbSelectorProducerIndex -ResponseShapeMap $script:shapeMap
        $script:endpointLiteral = Get-PfbCmdletEndpointLiteral -PublicDirectory (Join-Path $script:repoRoot 'Public')
        $script:exampleChain = Get-PfbHelpExampleChain -PublicDirectory (Join-Path $script:repoRoot 'Public')

        $script:inventory = Get-PfbCmdletParameterInventory -PublicDirectory (Join-Path $script:repoRoot 'Public')
        $script:producerSet = @{}
        foreach ($cmd in ($script:bound.Cmdlet | Sort-Object -Unique)) {
            $script:producerSet[$cmd] = Get-PfbSelectorProducerSet -Cmdlet $cmd `
                -EndpointLiteral $script:endpointLiteral -ProducerIndex $script:producerIndex `
                -ExampleChain $script:exampleChain
        }
        $script:candidates = Get-PfbSelectorCandidate -PipelineParameter $script:bound `
            -Inventory $script:inventory -ProducerSet $script:producerSet `
            -ResponseShapeMap $script:shapeMap
    }
}

Describe 'Ordinal sort helpers' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    # These had NO tests, which is how Sort-PfbSelectorRecord shipped as a silent no-op:
    # [array]::Sort($keys, $items, $comparer) sorts the keys in place and leaves the items
    # untouched, so the function returned its input in original order while its help claimed
    # otherwise. Nothing threw. Every artifact it ordered was simply unsorted.

    It 'actually reorders records, rather than returning them untouched' {
        $records = @(
            [PSCustomObject]@{ Cmdlet = 'A'; Parameter = 'RemoteName'; Producer = 'GET /x' }
            [PSCustomObject]@{ Cmdlet = 'A'; Parameter = 'Id'; Producer = 'GET /x' }
            [PSCustomObject]@{ Cmdlet = 'A'; Parameter = 'Name'; Producer = 'GET /a' }
        )
        $sorted = Sort-PfbSelectorRecord -Record $records -Property 'Cmdlet', 'Parameter', 'Producer'

        @($sorted | ForEach-Object { $_.Parameter }) -join ',' | Should -Be 'Id,Name,RemoteName'
    }

    It 'sorts by every named property in order, not just the first' {
        $records = @(
            [PSCustomObject]@{ Cmdlet = 'A'; Parameter = 'Name'; Producer = 'GET /z' }
            [PSCustomObject]@{ Cmdlet = 'A'; Parameter = 'Name'; Producer = 'GET /a' }
        )
        $sorted = Sort-PfbSelectorRecord -Record $records -Property 'Cmdlet', 'Parameter', 'Producer'

        @($sorted | ForEach-Object { $_.Producer }) -join ',' | Should -Be 'GET /a,GET /z'
    }

    It 'is ORDINAL, not linguistic: a hyphen sorts before a letter' {
        # The whole reason these helpers exist. 5.1 collation ignores the hyphen and orders
        # 'file-systems' first; ordinal comparison does not, and agrees on both editions.
        $records = @(
            [PSCustomObject]@{ Key = 'GET /policies/file-systems' }
            [PSCustomObject]@{ Key = 'GET /policies/file-system-snapshots' }
        )
        $sorted = Sort-PfbSelectorRecord -Record $records -Property 'Key'

        @($sorted | ForEach-Object { $_.Key })[0] | Should -Be 'GET /policies/file-system-snapshots'
    }

    It 'breaks ties by original position, because List<T>.Sort is unstable' {
        $records = @(
            [PSCustomObject]@{ Key = 'same'; Tag = 'first' }
            [PSCustomObject]@{ Key = 'same'; Tag = 'second' }
            [PSCustomObject]@{ Key = 'same'; Tag = 'third' }
        )
        $sorted = Sort-PfbSelectorRecord -Record $records -Property 'Key'

        @($sorted | ForEach-Object { $_.Tag }) -join ',' | Should -Be 'first,second,third'
    }

    It 'sorts strings ordinally and de-duplicates on request' {
        $sorted = Sort-PfbSelectorString -Value @('b', 'a', 'b', 'A') -Unique

        $sorted -join ',' | Should -Be 'A,a,b'
    }
}

Describe 'Get-PfbPipelineBoundParameter' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    It 'finds pipeline-bound parameters that the bare attribute form declares' {
        # Get-PfbNode declares: [Parameter(ParameterSetName='ByName', ValueFromPipeline,
        # ValueFromPipelineByPropertyName)] [string[]]$Name
        $rec = $script:bound | Where-Object { $_.Cmdlet -eq 'Get-PfbNode' -and $_.Parameter -eq 'Name' }
        $rec | Should -Not -BeNullOrEmpty
        $rec.ValueFromPipeline | Should -BeTrue
        $rec.ValueFromPipelineByPropertyName | Should -BeTrue
        $rec.ParameterType | Should -Be 'String[]'
    }

    It 'carries aliases, which participate in property-name binding' {
        $rec = $script:bound | Where-Object { $_.Cmdlet -eq 'Get-PfbArrayConnectionPath' -and $_.Parameter -eq 'RemoteName' }
        $rec.Aliases | Should -Contain 'Name'
    }

    It 'excludes parameters with no pipeline binding at all' {
        $rec = $script:bound | Where-Object { $_.Cmdlet -eq 'Get-PfbNode' -and $_.Parameter -eq 'Filter' }
        $rec | Should -BeNullOrEmpty
    }

    It 'reports the measured module-wide population' {
        # Re-baselined from 303 / 214 when the Stage 2 selector fixes landed. The whole
        # movement is accounted for, which is the only thing that makes a re-baseline
        # legitimate rather than a silenced tripwire -- measured by diffing this function's
        # output between origin/main and the fix branch:
        #
        #   +26 rows: renames of a selector that carried the wrong wire key
        #             (MemberName -> BucketName on 11 bucket-policy cmdlets, and
        #             Name -> CertificateName / GroupName / LocalPortName / RealmName),
        #             plus selectors that replace a removed dead one (-Id on
        #             Get/Remove-PfbOpenFile and Get/Remove-PfbResourceAccess) and
        #             parent-name selectors added so a policy-family pipeline binds by
        #             property name instead of falling through to coercion.
        #   -18 rows: the old name of each of those renames, and the dead selectors
        #             themselves (Get-PfbFleetKey/Name,
        #             Get-PfbNetworkConnectionStatistics/Name, Get-PfbOpenFile/Name, ...).
        #
        #   Net +8, giving 311. ValueFromPipeline: 214 + 12 added - 17 removed = 209.
        #
        # NO row changed its ValueFromPipeline value. That is deliberate and worth pinning:
        # removing ValueFromPipeline was rejected as a remedy on this branch, because binding
        # resolves in FOUR passes and pass 4 coerces a ByPropertyName-only parameter through
        # its alias -- so the attribute removal buys no structural immunity, and a guard is
        # what the affected parameters got instead.
        @($script:bound).Count | Should -Be 311
        @($script:bound | Where-Object ValueFromPipeline).Count | Should -Be 209
    }
}

Describe 'Producer resolution' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    It 'indexes GET endpoints by first path segment' {
        $script:producerIndex['array-connections'] | Should -Contain 'GET /array-connections'
        $script:producerIndex['array-connections'] | Should -Contain 'GET /array-connections/path'
    }

    It 'reports the measured GET-endpoint and family population' {
        @($script:producerIndex.Keys).Count | Should -Be 98
        @($script:producerIndex.Values | ForEach-Object { $_ }).Count | Should -Be 252
    }

    It 'finds the endpoint literal a cmdlet calls' {
        $script:endpointLiteral['Get-PfbArrayConnectionPath'] | Should -Contain 'array-connections/path'
    }

    It 'finds piped chains written in help examples' {
        @($script:exampleChain).Count | Should -Be 45

        $crossFamily = $script:exampleChain |
            Where-Object { $_.Producer -eq 'Get-PfbFileSystem' -and $_.Consumer -eq 'New-PfbFileSystemSnapshot' }
        $crossFamily | Should -Not -BeNullOrEmpty
    }

    It 'distinguishes the primary producer from the rest of the family' {
        $set = Get-PfbSelectorProducerSet -Cmdlet 'Get-PfbArrayConnectionPath' `
            -EndpointLiteral $script:endpointLiteral -ProducerIndex $script:producerIndex `
            -ExampleChain $script:exampleChain

        $set.Primary   | Should -Be @('GET /array-connections/path')
        $set.Producers | Should -Contain 'GET /array-connections'
        @($set.Producers).Count | Should -BeGreaterThan 1
    }
}

Describe 'Candidate predicate' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {

    It 'flags the known #64 case as a candidate' {
        $rec = $script:candidates | Where-Object {
            $_.Cmdlet -eq 'Get-PfbArrayConnectionPath' -and $_.Parameter -eq 'RemoteName' -and
            $_.Producer -eq 'GET /array-connections'
        }
        $rec.IsCandidate  | Should -BeTrue
        $rec.Gate         | Should -Be 'Candidate'
        $rec.MatchedField | Should -BeNullOrEmpty
    }

    It 'does not flag a selector that matches a real response field' {
        # array-connections items carry `id`, so -Id binds by property name.
        $rec = $script:candidates | Where-Object {
            $_.Cmdlet -eq 'Get-PfbArrayConnectionPath' -and $_.Parameter -eq 'Id' -and
            $_.Producer -eq 'GET /array-connections'
        }
        $rec.IsCandidate  | Should -BeFalse
        $rec.Gate         | Should -Be 'Matched'
        $rec.MatchedField | Should -Be 'id'
    }

    It 'excludes body properties via the selector-hood gate' {
        @($script:candidates | Where-Object { $_.WireSurface -eq 'Body' -and $_.IsCandidate }).Count |
            Should -Be 0
    }

    It 'keeps the predicate discriminating rather than vacuous' {
        $evaluated = @($script:candidates | Where-Object { $_.Gate -in @('Candidate', 'Matched') })
        $rate = @($evaluated | Where-Object IsCandidate).Count / $evaluated.Count
        $rate | Should -BeLessThan 0.75
    }
}

Describe 'Probe construction' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        . (Join-Path $script:repoRoot 'tools/lib/PfbSpecTools.ps1')
        $script:newestSpec = Join-Path $script:repoRoot 'tools/specs/fb2.28.json'
        $script:itemType = Get-PfbResponseItemType -SpecPath $script:newestSpec -Endpoint 'GET /array-connections'
    }

    It 'requires the spec cache to be populated' {
        @(Get-ChildItem (Join-Path $script:repoRoot 'tools/specs') -File).Count | Should -Be 29
    }

    It 'reads an object-typed response field as object, not string' {
        $script:itemType['remote'] | Should -Be 'object'
    }

    It 'reads a scalar response field as string' {
        $script:itemType['id'] | Should -Be 'string'
    }

    It 'gives each property a distinct sentinel so the bound property is identifiable' {
        $probe = New-PfbSelectorProbeObject -ItemProperty @('id', 'status') -ItemType @{ id = 'string'; status = 'string' }
        $probe.id     | Should -Be 'PROBE-id'
        $probe.status | Should -Be 'PROBE-status'
    }

    It 'materialises an object-typed field as a nested object, not a string' {
        $probe = New-PfbSelectorProbeObject -ItemProperty @('remote') -ItemType @{ remote = 'object' }
        $probe.remote | Should -BeOfType [System.Management.Automation.PSCustomObject]
    }

    It 'materialises an array-typed field as an array' {
        $probe = New-PfbSelectorProbeObject -ItemProperty @('replication_addresses') -ItemType @{ replication_addresses = 'array' }
        , $probe.replication_addresses | Should -BeOfType [System.Object[]]
    }
}

Describe 'Outcome classification' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'classifies a whole-object stringification as Coerced' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; status = 'PROBE-status' }
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ remote_names = '@{id=PROBE-id; status=PROBE-status}' } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'RemoteName' -WireName 'remote_names' -ProbeObject $probe
        $outcome.Outcome | Should -Be 'Coerced'
    }

    It 'classifies the matching sentinel as Bound' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id' }
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ ids = 'PROBE-id' } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'Id' -WireName 'ids' -ProbeObject $probe
        $outcome.Outcome | Should -Be 'Bound'
    }

    It 'classifies a sentinel from the wrong property as WrongScalar' {
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; status = 'PROBE-status' }
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ names = 'PROBE-status' } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'Name' -WireName 'names' -ProbeObject $probe
        $outcome.Outcome | Should -Be 'WrongScalar'
    }

    It 'treats a sentinel sourced from a declared alias as Bound' {
        # Get-PfbArrayConnectionPath's -RemoteName carries the alias Name, so a piped `name`
        # property binds it correctly even though the two names differ.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; name = 'PROBE-name' }
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ remote_names = 'PROBE-name' } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'RemoteName' -WireName 'remote_names' `
            -ProbeObject $probe -Alias @('Name')
        $outcome.Outcome | Should -Be 'Bound'
    }

    It 'does not let a matching wire key excuse a value from the wrong property' {
        # The expected key carrying an unrelated property's sentinel IS the defect; a key
        # match must never license a Bound verdict.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; status = 'PROBE-status' }
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ remote_names = 'PROBE-status' } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'RemoteName' -WireName 'remote_names' `
            -ProbeObject $probe -Alias @('Name')
        $outcome.Outcome | Should -Be 'WrongScalar'
    }

    It 'does not attribute another parameter''s correct binding to this row' {
        # Measured false positive: Get-PfbArrayConnectionPath's -RemoteName row was reported
        # WrongScalar on evidence "ids=PROBE-id" -- which is -Id binding exactly as it should,
        # while remote_names was never emitted at all. The verdict must come from this
        # parameter's OWN wire key.
        $probe = [PSCustomObject]@{ id = 'PROBE-id'; status = 'PROBE-status' }
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ ids = 'PROBE-id' } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'RemoteName' -WireName 'remote_names' `
            -ProbeObject $probe -Alias @('Name')
        $outcome.Outcome | Should -Be 'NoSelector'
    }

    It 'classifies a guard throw as Guarded, not a defect' {
        $result = [PSCustomObject]@{ Calls = @(); Error = 'Refusing to send a stringified object as remote_names.' }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'RemoteName' -WireName 'remote_names' `
            -ProbeObject ([PSCustomObject]@{ status = 'PROBE-status' })
        $outcome.Outcome | Should -Be 'Guarded'
    }

    It 'classifies a parameter-set failure as BindError' {
        $result = [PSCustomObject]@{ Calls = @(); Error = 'Parameter set cannot be resolved using the specified named parameters.' }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'Name' -WireName 'names' `
            -ProbeObject ([PSCustomObject]@{ id = 'PROBE-id' })
        $outcome.Outcome | Should -Be 'BindError'
    }

    It 'classifies an emitted call carrying no selector key as NoSelector' {
        $result = [PSCustomObject]@{
            Calls = @([PSCustomObject]@{ Method = 'GET'; Endpoint = 'x'; QueryParams = @{ limit = 10 } })
            Error = $null
        }
        $outcome = Get-PfbSelectorOutcome -ProbeResult $result -Parameter 'Name' -WireName 'names' `
            -ProbeObject ([PSCustomObject]@{ id = 'PROBE-id' })
        $outcome.Outcome | Should -Be 'NoSelector'
    }
}
