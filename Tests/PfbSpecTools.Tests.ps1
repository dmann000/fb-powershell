#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbSpecTools.ps1 — the shared spec-extraction and
    capability-diffing helpers used by tools/Update-PfbApiSpecs.ps1 and
    tools/Build-PfbCapabilityMap.ps1.
.DESCRIPTION
    These are pure-function unit tests against a small synthetic fixture
    (Tests/Fixtures/sample-redoc-page.html) and inline synthetic spec objects — no
    network access and no dependency on the real cached specs in tools/specs/.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')

    $fixturePath = Join-Path $PSScriptRoot 'Fixtures/sample-redoc-page.html'
    $script:fixtureHtml = Get-Content -Path $fixturePath -Raw
}

Describe 'ConvertFrom-PfbRedocHtml' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # ConvertFrom-PfbRedocHtml (tools/lib/PfbSpecTools.ps1) calls ConvertFrom-Json -Depth,
    # which does not exist on Windows PowerShell 5.1 (added in PS6) -- this function is
    # dev/CI-only tooling never loaded by the shipped module (see PureStorageFlashBladePowerShell.psm1,
    # which only sources Private/ and Public/), so it's out of scope for 5.1 support.
    It 'extracts the embedded OpenAPI document' {
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.openapi | Should -Be '3.0.1'
        $spec.info.version | Should -Be '9.9'
    }

    It 'correctly walks past braces embedded inside string values (does not truncate early)' {
        # The fixture's description contains a literal "{this}" and the trailing
        # options.theme.spacing value contains "({ spacing }) => 10" — both would break
        # a naive scan for the *first* unmatched-looking '}' instead of a real
        # string-aware balanced-brace scan.
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.info.description | Should -Match 'braces like \{this\} embedded'
        $spec.paths.'/api/9.9/widgets' | Should -Not -BeNullOrEmpty
    }

    It 'correctly handles escaped quotes and backslashes inside strings' {
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.info.'x-fixture-escape-test' | Should -Match 'a quoted word'
        $spec.info.'x-fixture-escape-test' | Should -Match '\\'
    }

    It 'decodes non-ASCII characters correctly' {
        $spec = ConvertFrom-PfbRedocHtml -Html $fixtureHtml
        $spec.info.description | Should -Match 'café'
    }

    It 'throws a clear error when the __redoc_state marker is missing' {
        { ConvertFrom-PfbRedocHtml -Html '<html><body>nothing here</body></html>' } |
            Should -Throw '*__redoc_state*'
    }

    It 'throws a clear error when the JSON is malformed' {
        # 'undefined' is not a valid JSON literal in any parser (unlike a trailing
        # comma, which some parsers tolerate) - this is unambiguously invalid.
        $badHtml = '<script>const __redoc_state = {"spec": {"data": undefined}};</script>'
        { ConvertFrom-PfbRedocHtml -Html $badHtml } | Should -Throw
    }
}

Describe 'ConvertTo-PfbNormalizedPath' {
    It 'strips the "/api/<version>/" prefix from versioned paths' {
        ConvertTo-PfbNormalizedPath -Path '/api/2.27/arrays' | Should -Be '/arrays'
        ConvertTo-PfbNormalizedPath -Path '/api/2.0/file-systems' | Should -Be '/file-systems'
    }

    It 'leaves unversioned auth/meta endpoints unchanged' {
        ConvertTo-PfbNormalizedPath -Path '/api/login' | Should -Be '/api/login'
        ConvertTo-PfbNormalizedPath -Path '/api/api_version' | Should -Be '/api/api_version'
        ConvertTo-PfbNormalizedPath -Path '/oauth2/1.0/token' | Should -Be '/oauth2/1.0/token'
    }
}

Describe 'Resolve-PfbRef' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    Names = [PSCustomObject]@{ name = 'names'; in = 'query' }
                }
                schemas    = [PSCustomObject]@{
                    Widget      = [PSCustomObject]@{ '$ref' = '#/components/schemas/WidgetAlias' }
                    WidgetAlias = [PSCustomObject]@{ type = 'object'; properties = [PSCustomObject]@{ id = @{ type = 'string' } } }
                }
            }
        }
    }

    It 'resolves a single-level $ref' {
        $node = [PSCustomObject]@{ '$ref' = '#/components/parameters/Names' }
        $resolved = Resolve-PfbRef -Node $node -Spec $testSpec
        $resolved.name | Should -Be 'names'
    }

    It 'follows chained $refs to the final target' {
        $node = [PSCustomObject]@{ '$ref' = '#/components/schemas/Widget' }
        $resolved = Resolve-PfbRef -Node $node -Spec $testSpec
        $resolved.type | Should -Be 'object'
    }

    It 'returns non-$ref nodes unchanged' {
        $node = [PSCustomObject]@{ name = 'plain'; in = 'query' }
        $resolved = Resolve-PfbRef -Node $node -Spec $testSpec
        $resolved.name | Should -Be 'plain'
    }

    It 'returns $null unchanged' {
        Resolve-PfbRef -Node $null -Spec $testSpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSchemaPropertyNames' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    BaseResource  = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{ id = @{ type = 'string' }; name = @{ type = 'string' } }
                    }
                    ResourcePatch = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{ enabled = @{ type = 'boolean' } }
                            }
                        )
                    }
                }
            }
        }
    }

    It 'reads direct properties off an inline schema' {
        $schema = [PSCustomObject]@{ properties = [PSCustomObject]@{ a = @{}; b = @{} } }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec
        $names | Should -Contain 'a'
        $names | Should -Contain 'b'
    }

    It 'resolves a $ref schema before reading properties' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec
        $names | Should -Contain 'id'
        $names | Should -Contain 'name'
    }

    It 'merges properties across allOf branches, including $ref branches' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec
        $names | Should -Contain 'id'
        $names | Should -Contain 'name'
        $names | Should -Contain 'enabled'
    }

    It 'returns an empty list for a null schema' {
        Get-PfbSchemaPropertyNames -Schema $null -Spec $testSpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSchemaPropertyDetails' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    # PIN fixture: itself readOnly, but only reachable through a property
                    # that is a BARE $ref (no sibling keys) -- must not leak through.
                    _readOnlyLeaf = [PSCustomObject]@{
                        type     = 'string'
                        readOnly = $true
                    }
                    BaseResource  = [PSCustomObject]@{
                        type       = 'object'
                        required   = @('id')
                        properties = [PSCustomObject]@{
                            id   = [PSCustomObject]@{ type = 'string' }
                            name = [PSCustomObject]@{ type = 'string'; format = 'name-format' }
                        }
                    }
                    ResourcePatch = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
                            [PSCustomObject]@{
                                type       = 'object'
                                required   = @('enabled')
                                properties = [PSCustomObject]@{
                                    enabled  = [PSCustomObject]@{ type = 'boolean'; readOnly = $true }
                                    status   = [PSCustomObject]@{ type = 'string'; deprecated = $true }
                                    ref_only = [PSCustomObject]@{ '$ref' = '#/components/schemas/_readOnlyLeaf' }
                                }
                            }
                        )
                    }
                    # Merge-rule fixture: 'shared' declared in two allOf branches of the
                    # SAME schema, read-only in only one of them.
                    MergeConflict = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{ shared = [PSCustomObject]@{ type = 'string' } }
                            }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{ shared = [PSCustomObject]@{ type = 'string'; readOnly = $true } }
                            }
                        )
                    }

                    # OwnerSchema fixture, shaped like the brief's worked example:
                    # CertificatePatch = allOf[ _certificateBase, {inline: days,...} ]
                    # _certificateBase = allOf[ _realmsReference, {inline: certificate_type,...} ]
                    # Three tiers -> three different expected owners.
                    _realmsReference  = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{ realms = [PSCustomObject]@{ type = 'array' } }
                    }
                    _certificateBase  = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/_realmsReference' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    certificate_type = [PSCustomObject]@{ type = 'string' }
                                    issued_by        = [PSCustomObject]@{ type = 'string' }
                                }
                            }
                        )
                    }
                    CertificatePatch  = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/_certificateBase' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    days       = [PSCustomObject]@{ type = 'integer' }
                                    passphrase = [PSCustomObject]@{ type = 'string' }
                                }
                            }
                        )
                    }

                    # Outermost-wins fixture: 'dup' declared directly by TWO different named
                    # components in the same chain -- OwnerSchema must pick the shallower one
                    # (OuterOwner, declared inline directly under OuterOwner's own allOf), not
                    # the deeper one reached through a further nested $ref (InnerOwner). The
                    # inline (OuterOwner-owned) branch is listed FIRST in the allOf array so
                    # this is unambiguous under the "first-seen in traversal order" tie-break
                    # documented on Add-PfbSchemaPropertyNodes (own/inherited-owner properties
                    # are always recorded before a sibling branch's nested named $ref is
                    # walked into).
                    InnerOwner        = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{ dup = [PSCustomObject]@{ type = 'string' } }
                    }
                    OuterOwner        = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{ dup = [PSCustomObject]@{ type = 'string' } }
                            }
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/InnerOwner' }
                        )
                    }

                    # Fully inline fixture: no $ref anywhere in the chain -- OwnerSchema must
                    # come out $null (explicitly, not '').
                    FullyInline       = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{ freeform = [PSCustomObject]@{ type = 'string' } }
                    }
                }
            }
        }
    }

    It 'resolves ReadOnly and Deprecated through an allOf/$ref chain' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'enabled').ReadOnly | Should -Be $true
        ($details | Where-Object Name -eq 'status').Deprecated | Should -Be $true
        ($details | Where-Object Name -eq 'id').ReadOnly | Should -Be $false
    }

    It 'merge rule: a property marked read-only in one allOf branch and not another comes out read-only' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/MergeConflict' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'shared').ReadOnly | Should -Be $true
    }

    It 'PIN: does not follow a property''s own $ref to a read-only-bearing schema' {
        # ref_only's own node is a bare '$ref' to _readOnlyLeaf, which IS readOnly:true.
        # Resolving into it would (wrongly) report ref_only as read-only.
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'ref_only').ReadOnly | Should -Be $false
    }

    It 'PIN regression: ref_only still resolves ReadOnly=$false AND now also carries its correct OwnerSchema' {
        # Adding OwnerSchema tracking touches the same ref-resolution code path as the PIN
        # above -- this is exactly where a regression would hide. Re-assert both facts
        # together: the owner is recorded from the CHAIN being walked into (the allOf
        # branch of ResourcePatch that declares ref_only), never from resolving ref_only's
        # own '$ref' value (which would incorrectly suggest an owner of '_readOnlyLeaf').
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        $refOnly = $details | Where-Object Name -eq 'ref_only'
        $refOnly.ReadOnly | Should -Be $false
        $refOnly.OwnerSchema | Should -Be 'ResourcePatch'
    }

    It 'OwnerSchema resolves to the nearest named component through an allOf + $ref chain (three tiers)' {
        # Mirrors the brief's PATCH /certificates worked example exactly:
        # CertificatePatch = allOf[ _certificateBase, {inline: days, passphrase} ]
        # _certificateBase = allOf[ _realmsReference, {inline: certificate_type, issued_by} ]
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/CertificatePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'days').OwnerSchema | Should -Be 'CertificatePatch'
        ($details | Where-Object Name -eq 'passphrase').OwnerSchema | Should -Be 'CertificatePatch'
        ($details | Where-Object Name -eq 'certificate_type').OwnerSchema | Should -Be '_certificateBase'
        ($details | Where-Object Name -eq 'issued_by').OwnerSchema | Should -Be '_certificateBase'
        ($details | Where-Object Name -eq 'realms').OwnerSchema | Should -Be '_realmsReference'
    }

    It 'attributes a property declared in an anonymous inline branch to the nearest NAMED ancestor, not the branch itself' {
        # 'days' is declared in CertificatePatch's own anonymous inline allOf branch --
        # there is no schema named after that branch; the only correct owner is the
        # nearest enclosing NAMED component, CertificatePatch itself.
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/CertificatePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'days').OwnerSchema | Should -Be 'CertificatePatch'
        ($details | Where-Object Name -eq 'days').OwnerSchema | Should -Not -Be $null
    }

    It 'a fully inline body with no $ref anywhere yields OwnerSchema $null, explicitly (not '''')' {
        # Deliberately pass the schema NODE ITSELF, not a '$ref' wrapper around it -- this
        # simulates an operation whose request body is written fully inline in the spec
        # (no $ref anywhere in its chain), the only case where OwnerSchema is $null.
        $schema = $testSpec.components.schemas.FullyInline
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        $freeform = $details | Where-Object Name -eq 'freeform'
        $freeform.OwnerSchema | Should -BeNullOrEmpty
        $null -eq $freeform.OwnerSchema | Should -Be $true
        $freeform.OwnerSchema -eq '' | Should -Be $false
    }

    It 'outermost-wins: when two named schemas declare the same property, the shallower one wins' {
        # OuterOwner = allOf[ {inline: dup}, InnerOwner ] -- 'dup' is declared both directly
        # (inline, owned by OuterOwner itself) and via a nested named $ref to InnerOwner.
        # The outer (closer to the operation's own body schema) declaration must win.
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/OuterOwner' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'dup').OwnerSchema | Should -Be 'OuterOwner'
    }

    It 'populates Type and Format from the property''s own node' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'name').Type | Should -Be 'string'
        ($details | Where-Object Name -eq 'name').Format | Should -Be 'name-format'
    }

    It 'collects Required across allOf branches' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        ($details | Where-Object Name -eq 'id').Required | Should -Be $true
        ($details | Where-Object Name -eq 'enabled').Required | Should -Be $true
        ($details | Where-Object Name -eq 'name').Required | Should -Be $false
        ($details | Where-Object Name -eq 'status').Required | Should -Be $false
    }

    It 'returns an empty list for a null schema' {
        Get-PfbSchemaPropertyDetails -Schema $null -Spec $testSpec | Should -BeNullOrEmpty
    }

    It 'sorts its output by Name regardless of traversal order (the sort invariant)' {
        # ResourcePatch's declaration/traversal order is id, name, enabled, status, ref_only --
        # deliberately NOT alphabetical, so this assertion actually exercises the sort.
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $details = Get-PfbSchemaPropertyDetails -Schema $schema -Spec $testSpec

        @($details.Name) | Should -Be (@($details.Name) | Sort-Object)
    }

    It 'Get-PfbSchemaPropertyNames (the wrapper) returns TRAVERSAL order on the same fixture, NOT sorted' {
        # Companion to the sort-invariant test above: Get-PfbSchemaPropertyDetails sorts,
        # Get-PfbSchemaPropertyNames deliberately does not (controller ruling -- see that
        # function's help). Pinning both on the same non-alphabetical fixture is what stops
        # either behaviour silently flipping later.
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $names = Get-PfbSchemaPropertyNames -Schema $schema -Spec $testSpec

        @($names) | Should -Be @('id', 'name', 'enabled', 'status', 'ref_only')
    }
}

Describe 'Get-PfbSpecCapabilities' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            paths      = [PSCustomObject]@{
                '/api/9.9/widgets' = [PSCustomObject]@{
                    'x-pure-authorization-resource' = 'widgets'
                    get                              = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/Filter' }
                            # Inline, no $ref -- must contribute to Parameters but have no
                            # entry in ParameterComponents at all (not null/'').
                            [PSCustomObject]@{ name = 'raw_only'; in = 'query' }
                        )
                    }
                    post                             = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/WidgetPost' }
                                }
                            }
                        }
                    }
                }
            }
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    Filter = [PSCustomObject]@{ name = 'filter'; in = 'query' }
                }
                schemas    = [PSCustomObject]@{
                    WidgetPost = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            name   = [PSCustomObject]@{ type = 'string' }
                            color  = [PSCustomObject]@{ type = 'string' }
                            id     = [PSCustomObject]@{ type = 'string'; readOnly = $true }
                            status = [PSCustomObject]@{ type = 'string'; deprecated = $true }
                        }
                    }
                }
            }
        }
    }

    It 'skips vendor extension keys like x-pure-authorization-resource' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        ($caps | ForEach-Object { $_.Method }) | Should -Not -Contain 'X-PURE-AUTHORIZATION-RESOURCE'
    }

    It 'produces one record per (method, normalized path)' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $caps.Count | Should -Be 2
        ($caps | Where-Object Method -eq 'GET').Path | Should -Be '/widgets'
        ($caps | Where-Object Method -eq 'POST').Path | Should -Be '/widgets'
    }

    It 'resolves $ref parameters to their names' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $getCap = $caps | Where-Object Method -eq 'GET'
        $getCap.Parameters | Should -Contain 'filter'
    }

    It 'resolves $ref request-body schemas to their property names' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $postCap = $caps | Where-Object Method -eq 'POST'
        $postCap.BodyProperties | Should -Contain 'name'
        $postCap.BodyProperties | Should -Contain 'color'
    }

    It 'populates BodyPropertyDetails for a mix of read-only, deprecated and plain properties' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $postCap = $caps | Where-Object Method -eq 'POST'
        $postCap.BodyPropertyDetails.Count | Should -Be 4
        ($postCap.BodyPropertyDetails | Where-Object Name -eq 'name').ReadOnly | Should -Be $false
        ($postCap.BodyPropertyDetails | Where-Object Name -eq 'id').ReadOnly | Should -Be $true
        ($postCap.BodyPropertyDetails | Where-Object Name -eq 'status').Deprecated | Should -Be $true
    }

    It 'projects ReadOnlyBodyProperties and DeprecatedBodyProperties' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $postCap = $caps | Where-Object Method -eq 'POST'
        $postCap.ReadOnlyBodyProperties | Should -Be @('id')
        $postCap.DeprecatedBodyProperties | Should -Be @('status')
    }

    It 'populates ParameterComponents with the $ref''d parameter''s component name' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $getCap = $caps | Where-Object Method -eq 'GET'
        $getCap.ParameterComponents['filter'] | Should -Be 'Filter'
    }

    It 'omits the ParameterComponents key entirely for an inline (no $ref) parameter' {
        $caps = Get-PfbSpecCapabilities -Spec $testSpec
        $getCap = $caps | Where-Object Method -eq 'GET'
        $getCap.Parameters | Should -Contain 'raw_only'
        $getCap.ParameterComponents.ContainsKey('raw_only') | Should -Be $false
    }

    It 'deterministically resolves (and warns on) a parameter name that resolves to two different components' {
        $conflictSpec = [PSCustomObject]@{
            paths      = [PSCustomObject]@{
                '/api/9.9/conflict' = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/ZParam' }
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/AParam' }
                        )
                    }
                }
            }
            components = [PSCustomObject]@{
                parameters = [PSCustomObject]@{
                    ZParam = [PSCustomObject]@{ name = 'dup'; in = 'query' }
                    AParam = [PSCustomObject]@{ name = 'dup'; in = 'query' }
                }
            }
        }

        $caps = Get-PfbSpecCapabilities -Spec $conflictSpec -WarningVariable warnings -WarningAction SilentlyContinue
        $caps[0].ParameterComponents['dup'] | Should -Be 'AParam'
        ($warnings -join ' ') | Should -Match 'multiple different components'
    }

    It 'returns an empty list for a spec with no paths' {
        $emptySpec = [PSCustomObject]@{ paths = [PSCustomObject]@{} }
        Get-PfbSpecCapabilities -Spec $emptySpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSwaggerIndexVersions' {
    It 'extracts and sorts version numbers correctly, including double-digit minors' {
        $html = @'
<a href="redoc/fb2.9-api-reference.html">2.9</a>
<a href="redoc/fb2.10-api-reference.html">2.10</a>
<a href="redoc/fb2.2-api-reference.html">2.2</a>
'@
        $versions = Get-PfbSwaggerIndexVersions -IndexHtml $html
        # Numeric sort must place 2.10 after 2.9, not lexicographically before it.
        $versions | Should -Be @('2.2', '2.9', '2.10')
    }

    It 'de-duplicates repeated links' {
        $html = '<a href="redoc/fb2.5-api-reference.html">x</a><a href="redoc/fb2.5-api-reference.html">y</a>'
        $versions = Get-PfbSwaggerIndexVersions -IndexHtml $html
        $versions | Should -Be @('2.5')
    }

    It 'returns an empty list when no versions are found' {
        Get-PfbSwaggerIndexVersions -IndexHtml '<html></html>' | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbResponseSchema' {
    It 'returns the first 2xx application/json response schema' {
        $op = [PSCustomObject]@{
            responses = [PSCustomObject]@{
                '200' = [PSCustomObject]@{
                    content = [PSCustomObject]@{
                        'application/json' = [PSCustomObject]@{
                            schema = [PSCustomObject]@{ marker = 'yes' }
                        }
                    }
                }
                '400' = [PSCustomObject]@{ description = 'bad' }
            }
        }
        $result = Get-PfbResponseSchema -Operation $op -Spec ([PSCustomObject]@{})
        $result.marker | Should -Be 'yes'
    }

    It 'returns $null when no 2xx response carries a schema' {
        $op = [PSCustomObject]@{
            responses = [PSCustomObject]@{ '400' = [PSCustomObject]@{ description = 'bad' } }
        }
        Get-PfbResponseSchema -Operation $op -Spec ([PSCustomObject]@{}) | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSpecResponseShapes' {
    BeforeAll {
        $script:shapeSpec = [PSCustomObject]@{
            paths = [PSCustomObject]@{
                '/api/2.0/file-systems' = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        responses = [PSCustomObject]@{
                            '200' = [PSCustomObject]@{
                                content = [PSCustomObject]@{
                                    'application/json' = [PSCustomObject]@{
                                        schema = [PSCustomObject]@{
                                            properties = [PSCustomObject]@{
                                                items              = [PSCustomObject]@{
                                                    type  = 'array'
                                                    items = [PSCustomObject]@{
                                                        properties = [PSCustomObject]@{
                                                            name      = [PSCustomObject]@{ type = 'string' }
                                                            destroyed = [PSCustomObject]@{ type = 'boolean' }
                                                        }
                                                    }
                                                }
                                                total_item_count   = [PSCustomObject]@{ type = 'integer' }
                                                errors             = [PSCustomObject]@{ type = 'array' }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    It 'extracts envelope properties including errors' {
        $shapes = @(Get-PfbSpecResponseShapes -Spec $script:shapeSpec)
        $shapes.Count | Should -Be 1
        $shapes[0].Method | Should -Be 'GET'
        $shapes[0].Path | Should -Be '/file-systems'
        $shapes[0].EnvelopeProperties | Should -Contain 'errors'
        $shapes[0].EnvelopeProperties | Should -Contain 'total_item_count'
    }

    It 'descends one level into items[] and no further' {
        $shapes = @(Get-PfbSpecResponseShapes -Spec $script:shapeSpec)
        $shapes[0].ItemProperties | Should -Contain 'name'
        $shapes[0].ItemProperties | Should -Contain 'destroyed'
        # depth 3 is deliberately excluded -- nothing dotted is ever emitted
        @($shapes[0].ItemProperties | Where-Object { $_ -like '*.*' }).Count | Should -Be 0
    }

    It 'emits deterministically sorted collections' {
        $shapes = @(Get-PfbSpecResponseShapes -Spec $script:shapeSpec)
        $shapes[0].EnvelopeProperties | Should -Be (@($shapes[0].EnvelopeProperties) | Sort-Object)
        $shapes[0].ItemProperties | Should -Be (@($shapes[0].ItemProperties) | Sort-Object)
    }
}

Describe 'Get-PfbSpecResponseShapes -MaxDepth (regression: the 184-false-removal trap)' {
    BeforeAll {
        # An allOf chain 10 levels deep -- deeper than the walker's default MaxDepth of 8.
        # This mirrors components.schemas.FileSystem in fb2.13-2.16, which reads 4 properties
        # at depth 8 and 21 at depth 16. Reading it at the default would report the deep
        # property as absent, which the accumulator would then record as a REMOVAL.
        $schemas = [PSCustomObject]@{}
        $schemas | Add-Member -NotePropertyName 'Level9' -NotePropertyValue ([PSCustomObject]@{
                properties = [PSCustomObject]@{ deep_field = [PSCustomObject]@{ type = 'string' } }
            })
        foreach ($i in 8..0) {
            $schemas | Add-Member -NotePropertyName "Level$i" -NotePropertyValue ([PSCustomObject]@{
                    allOf = @([PSCustomObject]@{ '$ref' = "#/components/schemas/Level$($i + 1)" })
                })
        }
        $script:deepSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{ schemas = $schemas }
            paths      = [PSCustomObject]@{
                '/api/2.0/deep' = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        responses = [PSCustomObject]@{
                            '200' = [PSCustomObject]@{
                                content = [PSCustomObject]@{
                                    'application/json' = [PSCustomObject]@{
                                        schema = [PSCustomObject]@{
                                            properties = [PSCustomObject]@{
                                                items = [PSCustomObject]@{
                                                    type  = 'array'
                                                    # 'shallow_field' sits inline on the items element schema, ALONGSIDE the
                                                    # deep allOf chain, and is reachable at any MaxDepth. It exists purely to
                                                    # give the depth-8 test below a positive anchor: without it, that test's
                                                    # only assertion is a negative one, and an implementation that returned
                                                    # nothing at all would satisfy it just as well as a correctly
                                                    # depth-truncated one. See that It's own comment.
                                                    items = [PSCustomObject]@{
                                                        properties = [PSCustomObject]@{ shallow_field = [PSCustomObject]@{ type = 'string' } }
                                                        allOf      = @([PSCustomObject]@{ '$ref' = '#/components/schemas/Level0' })
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    It 'finds a property nested deeper than the default MaxDepth of 8' {
        $shapes = @(Get-PfbSpecResponseShapes -Spec $script:deepSpec)
        $shapes[0].ItemProperties | Should -Contain 'deep_field'
        # At the real default BOTH are reached; contrast with the depth-8 test below, where
        # only the shallow one survives. The pair is what makes the difference attributable
        # to depth rather than to the walk having failed outright.
        $shapes[0].ItemProperties | Should -Contain 'shallow_field'
    }

    It 'would MISS that property at the default depth -- proving the constraint is real' {
        $shapes = @(Get-PfbSpecResponseShapes -Spec $script:deepSpec -MaxDepth 8)

        # POSITIVE ANCHORS FIRST, and they are the entire point of this ordering. The
        # assertion this test exists for is a NEGATIVE one, and a negative assertion about a
        # collection is satisfied by every degenerate outcome as well as by the intended one:
        # if the function returned an empty list, $shapes[0] would be $null and
        # `$null | Should -Not -Contain 'deep_field'` would pass, testing nothing. (Confirmed
        # by mutation: gutting Get-PfbSpecResponseShapes to return an empty list left this
        # test green.) These two anchors fail on that mutant, so reaching the negative below
        # proves the walk really ran, really produced this endpoint's record, and really
        # populated ItemProperties -- and that the ONLY thing missing at depth 8 is the
        # property that needs more than 8 levels to reach.
        $shapes.Count | Should -Be 1
        $shapes[0].ItemProperties | Should -Contain 'shallow_field'

        $shapes[0].ItemProperties | Should -Not -Contain 'deep_field'
    }
}

Describe 'Get-PfbSpecCapabilities -MaxDepth (regression: issue #71 body-schema allOf truncation)' {
    BeforeAll {
        # Same 10-level allOf chain as the response-shape regression above, but reached
        # through a REQUEST BODY rather than a response. This mirrors the fb2.12-2.16
        # PATCH /password-policies body, whose allOf chain runs deeper than 8 and whose five
        # properties therefore recorded introducedVersion 2.17 instead of 2.16. That is
        # runtime-visible, not cosmetic: Private/Assert-PfbApiCapability.ps1 reads
        # bodyProperties, so it would refuse those five parameters against a 2.16 array.
        # The 2.17 spec restructuring flattened these chains, which is why the defect
        # self-heals from 2.17 on and stays invisible against current data.
        $schemas = [PSCustomObject]@{}
        $schemas | Add-Member -NotePropertyName 'Level9' -NotePropertyValue ([PSCustomObject]@{
                properties = [PSCustomObject]@{ deep_field = [PSCustomObject]@{ type = 'string' } }
            })
        foreach ($i in 8..0) {
            $schemas | Add-Member -NotePropertyName "Level$i" -NotePropertyValue ([PSCustomObject]@{
                    allOf = @([PSCustomObject]@{ '$ref' = "#/components/schemas/Level$($i + 1)" })
                })
        }
        $script:deepBodySpec = [PSCustomObject]@{
            components = [PSCustomObject]@{ schemas = $schemas }
            paths      = [PSCustomObject]@{
                '/api/9.9/deep-body' = [PSCustomObject]@{
                    patch = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{
                                        # 'shallow_field' sits inline alongside the deep allOf chain and is
                                        # reachable at any MaxDepth. It is the positive anchor for the
                                        # depth-8 test below -- see that It's own comment for why a negative
                                        # assertion without one proves nothing.
                                        properties = [PSCustomObject]@{ shallow_field = [PSCustomObject]@{ type = 'string' } }
                                        allOf      = @([PSCustomObject]@{ '$ref' = '#/components/schemas/Level0' })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    It 'finds a body property nested deeper than the old default MaxDepth of 8' {
        $caps = @(Get-PfbSpecCapabilities -Spec $script:deepBodySpec)
        $caps.Count | Should -Be 1
        $caps[0].BodyProperties | Should -Contain 'shallow_field'
        $caps[0].BodyProperties | Should -Contain 'deep_field'
    }

    It 'also surfaces the deep property in BodyPropertyDetails, not only in BodyProperties' {
        # BodyProperties and BodyPropertyDetails come from two SEPARATE helper calls
        # (Get-PfbSchemaPropertyNames and Get-PfbSchemaPropertyDetails), each with its own
        # MaxDepth default. Asserting only the former would leave a fix that raises depth on
        # one call site and not the other looking green, while ReadOnlyBodyProperties and
        # DeprecatedBodyProperties -- both projections of Details -- stayed truncated.
        $caps = @(Get-PfbSpecCapabilities -Spec $script:deepBodySpec)
        ($caps[0].BodyPropertyDetails | ForEach-Object Name) | Should -Contain 'shallow_field'
        ($caps[0].BodyPropertyDetails | ForEach-Object Name) | Should -Contain 'deep_field'
    }

    It 'would MISS that property at depth 8 -- proving the constraint is real' {
        $caps = @(Get-PfbSpecCapabilities -Spec $script:deepBodySpec -MaxDepth 8)

        # POSITIVE ANCHORS FIRST, for the same reason as the response-shape regression above:
        # a negative assertion about a collection is satisfied by every degenerate outcome as
        # well as the intended one. If the walk returned nothing, $caps[0] would be $null and
        # the -Not -Contain below would pass while testing nothing. These anchors fail on that
        # mutant, so reaching the negative proves the walk ran, produced this endpoint's
        # record, populated BodyProperties, and that the ONLY casualty at depth 8 is the
        # property needing more than 8 levels to reach.
        $caps.Count | Should -Be 1
        $caps[0].BodyProperties | Should -Contain 'shallow_field'

        $caps[0].BodyProperties | Should -Not -Contain 'deep_field'
    }
}

Describe 'Get-PfbSpecCapabilities array-bodied requests (regression: issue #82)' {
    BeforeAll {
        # Mirrors POST /nodes/batch on fb2.18+: the request body schema is ITSELF `type: array`,
        # with `items` as a sibling keyword rather than a property. The walker's branches cover
        # $ref/allOf/properties/required but not `items`, so such a body resolved to a node with
        # no properties and no allOf, the accumulator added nothing, and the endpoint recorded
        # "bodyProperties": {} -- hiding every field from the runtime gate and the drift report.
        # Unlike #71 this does not self-heal on newer specs.
        #
        # The element schema is allOf-composed exactly like the real NodePost
        # (allOf [Node, {node_key}]), because the existing allOf handling has to run AFTER the
        # items hop. A fix that descends into items but stops composing allOf would find
        # node_key and miss name/id/status; one that composes allOf but never hops items finds
        # nothing at all. Asserting both members catches either half being wrong.
        $script:arrayBodySpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    BatchNode     = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            name   = [PSCustomObject]@{ type = 'string' }
                            id     = [PSCustomObject]@{ type = 'string'; readOnly = $true }
                            status = [PSCustomObject]@{ type = 'string'; readOnly = $true }
                        }
                    }
                    BatchNodePost = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/BatchNode' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{ node_key = [PSCustomObject]@{ type = 'string' } }
                            }
                        )
                    }
                    BatchEnvelope = [PSCustomObject]@{
                        type  = 'array'
                        items = [PSCustomObject]@{ '$ref' = '#/components/schemas/BatchNodePost' }
                    }
                }
            }
            paths      = [PSCustomObject]@{
                # Inline array body -- the shape all four real endpoints actually use.
                '/api/9.9/nodes/batch'     = [PSCustomObject]@{
                    post = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{
                                        type  = 'array'
                                        items = [PSCustomObject]@{ '$ref' = '#/components/schemas/BatchNodePost' }
                                    }
                                }
                            }
                        }
                    }
                }
                # $ref'd array body -- not used by any endpoint today, but the 2.17 restructuring
                # is precedent for this arrangement changing between spec versions. Distinguishes
                # a fix that resolves the media schema before testing `type` from one that reads
                # `.type` off an unresolved $ref node and finds $null.
                '/api/9.9/nodes/batch-ref' = [PSCustomObject]@{
                    post = [PSCustomObject]@{
                        requestBody = [PSCustomObject]@{
                            content = [PSCustomObject]@{
                                'application/json' = [PSCustomObject]@{
                                    schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BatchEnvelope' }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    It 'finds the element schema properties when the request body is itself an array' {
        $caps = @(Get-PfbSpecCapabilities -Spec $script:arrayBodySpec)
        $batch = $caps | Where-Object Path -eq '/nodes/batch'
        $batch.BodyProperties | Should -Contain 'node_key'
        $batch.BodyProperties | Should -Contain 'name'
        $batch.BodyProperties | Should -Contain 'id'
        $batch.BodyProperties | Should -Contain 'status'
    }

    It 'resolves ReadOnlyBodyProperties for an array-bodied endpoint' {
        # ReadOnlyBodyProperties is a projection of BodyPropertyDetails, which comes from a
        # SEPARATE helper call than BodyProperties. Asserting it proves the items hop reached
        # both call sites, not just the names one. All four real endpoints currently record
        # null here, and NodePost carries obviously read-only members, so this is asserted
        # rather than assumed.
        $caps = @(Get-PfbSpecCapabilities -Spec $script:arrayBodySpec)
        $batch = $caps | Where-Object Path -eq '/nodes/batch'
        $batch.ReadOnlyBodyProperties | Should -Contain 'id'
        $batch.ReadOnlyBodyProperties | Should -Contain 'status'
        $batch.ReadOnlyBodyProperties | Should -Not -Contain 'name'
        $batch.ReadOnlyBodyProperties | Should -Not -Contain 'node_key'
    }

    It 'resolves a $ref''d array body schema before testing it for items' {
        $caps = @(Get-PfbSpecCapabilities -Spec $script:arrayBodySpec)
        $batch = $caps | Where-Object Path -eq '/nodes/batch-ref'
        $batch.BodyProperties | Should -Contain 'node_key'
        $batch.BodyProperties | Should -Contain 'name'
    }
}
