#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbPipelineSelectorTools.ps1 -- the analysis layer of the
    issue #90 pipeline-selector audit.
.DESCRIPTION
    Fixtures shared by more than one Describe live in the FILE-level BeforeAll below.
    A Describe's own BeforeAll is not reliably visible to another Describe across the two
    Pester/StrictMode combinations this repo gates on.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
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

Describe 'Get-PfbPipelineBoundParameter' {

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
        @($script:bound).Count | Should -Be 303
        @($script:bound | Where-Object ValueFromPipeline).Count | Should -Be 214
    }
}

Describe 'Producer resolution' {

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

Describe 'Candidate predicate' {

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

Describe 'Probe construction' {
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

Describe 'Outcome classification' {
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
