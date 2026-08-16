#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for Get-PfbDeclaredQueryKey (tools/lib/PfbSpecTools.ps1).
.DESCRIPTION
    Pure-function unit tests against in-memory synthetic spec objects — no network access
    and no dependency on the cached specs in tools/specs/, so this file runs with no spec
    cache present.

    Every fixture node is a [PSCustomObject], never a bare @{} hashtable: Resolve-PfbRef
    tests for a '$ref' property via $current.PSObject.Properties.Name -contains '$ref',
    which never matches on a hashtable (see tools/lib/PfbSpecTools.ps1 for the trap note).
    A hashtable fixture would silently drop every $ref'd parameter and the $ref test would
    pass while proving nothing.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
}

Describe 'Get-PfbDeclaredQueryKey' {

    BeforeAll {
        $script:spec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    NamesParam = [PSCustomObject]@{
                        name = 'names'
                        'in' = 'query'
                    }
                }
            }
            paths      = [PSCustomObject]@{
                '/api/2.28/inline'     = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'filter'; 'in' = 'query' }
                            [PSCustomObject]@{ name = 'limit'; 'in' = 'query' }
                        )
                    }
                }
                '/api/2.28/reffed'     = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/NamesParam' }
                        )
                    }
                }
                '/api/2.28/pathparam'  = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'id'; 'in' = 'path' }
                            [PSCustomObject]@{ name = 'filter'; 'in' = 'query' }
                        )
                    }
                }
                '/api/2.28/noparams'   = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        responses = [PSCustomObject]@{ '200' = [PSCustomObject]@{} }
                    }
                }
                '/api/2.28/single'     = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'names'; 'in' = 'query' }
                        )
                    }
                }
                '/api/2.28/getonly'    = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'names'; 'in' = 'query' }
                        )
                    }
                }
                '/api/2.28/emptyverb'  = [PSCustomObject]@{
                    delete = [PSCustomObject]@{}
                }
                '/api/2.28/casing'     = [PSCustomObject]@{
                    delete = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'ids'; 'in' = 'query' }
                        )
                    }
                }
            }
        }
    }

    It 'returns an inline query parameter' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'inline' -Method 'GET' -Version '2.28'
        $result | Should -Contain 'filter'
        $result | Should -Contain 'limit'
        $result.Count | Should -Be 2
    }

    It 'resolves and returns a $ref''d query parameter' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'reffed' -Method 'GET' -Version '2.28'
        $result | Should -Contain 'names'
        $result.Count | Should -Be 1
    }

    It 'excludes a path-located parameter' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'pathparam' -Method 'GET' -Version '2.28'
        $result | Should -Contain 'filter'
        $result | Should -Not -Contain 'id'
        $result.Count | Should -Be 1
    }

    It 'returns an empty array, not $null, for an operation with no parameters' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'noparams' -Method 'GET' -Version '2.28'
        $null -eq $result | Should -BeFalse
        $result -is [string[]] | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'returns an array, not a bare string, for a single declared key' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'single' -Method 'GET' -Version '2.28'
        $result -is [string] | Should -BeFalse
        $result -is [string[]] | Should -BeTrue
        $result.Count | Should -Be 1
    }

    It 'returns $null for an absent path' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'does-not-exist' -Method 'GET' -Version '2.28'
        $null -eq $result | Should -BeTrue
    }

    It 'returns $null for a present path with an absent verb' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'getonly' -Method 'DELETE' -Version '2.28'
        $null -eq $result | Should -BeTrue
    }

    It 'returns an empty array, not $null, for a present but empty operation node' {
        $result = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'emptyverb' -Method 'DELETE' -Version '2.28'
        $null -eq $result | Should -BeFalse
        $result -is [string[]] | Should -BeTrue
        $result.Count | Should -Be 0
    }

    It 'resolves an endpoint literal with no leading slash' {
        $withoutSlash = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'inline' -Method 'GET' -Version '2.28'
        $withSlash = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint '/inline' -Method 'GET' -Version '2.28'
        $withoutSlash | Should -Contain 'filter'
        ($withoutSlash -join ',') | Should -Be ($withSlash -join ',')
    }

    It 'treats method casing as insensitive' {
        $upper = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'casing' -Method 'DELETE' -Version '2.28'
        $lower = Get-PfbDeclaredQueryKey -Spec $script:spec -Endpoint 'casing' -Method 'delete' -Version '2.28'
        $upper | Should -Contain 'ids'
        ($upper -join ',') | Should -Be ($lower -join ',')
    }
}
