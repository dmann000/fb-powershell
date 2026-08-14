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
