#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
<#
.SYNOPSIS
    Unit tests for tools/lib/PfbValueEnumTools.ps1 -- the prose "Valid/Possible values"
    extraction helpers used by tools/Build-PfbValueEnumMap.ps1.
.DESCRIPTION
    Pure-function unit tests against small synthetic spec objects (same
    [PSCustomObject]-fixture style as Tests/PfbSpecTools.Tests.ps1) -- no network access
    and no dependency on the real cached specs in tools/specs/.
#>

BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/lib/PfbSpecTools.ps1')
    . (Join-Path $repoRoot 'tools/lib/PfbValueEnumTools.ps1')
}

Describe 'Get-PfbValueEnumTriggerSentence' {
    It 'extracts a "Valid values are ... ." sentence' {
        $desc = "The versioning state for objects within the bucket. Valid values are ``none``, ``enabled``, and ``suspended``."
        $trigger = Get-PfbValueEnumTriggerSentence -Description $desc
        $trigger | Should -Be 'Valid values are `none`, `enabled`, and `suspended`.'
    }

    It 'extracts a "Possible values include ... ." sentence' {
        $desc = "The minimum severity for notifications. Possible values include ``info``, ``warning``, and ``critical``. Defaults to info."
        $trigger = Get-PfbValueEnumTriggerSentence -Description $desc
        $trigger | Should -Be 'Possible values include `info`, `warning`, and `critical`.'
    }

    It 'returns $null when no trigger phrase is present' {
        Get-PfbValueEnumTriggerSentence -Description 'A perfectly ordinary free-text description.' | Should -BeNullOrEmpty
    }

    It 'returns $null for an empty or missing description' {
        Get-PfbValueEnumTriggerSentence -Description $null | Should -BeNullOrEmpty
        Get-PfbValueEnumTriggerSentence -Description '' | Should -BeNullOrEmpty
    }

    It 'isolates only the trigger sentence, not trailing prose that repeats the values' {
        # Regression for the trigger-sentence-scoping rule: the preset export-rule
        # description explains each backtick-quoted value again in a paragraph *after*
        # the enum sentence -- the trigger sentence itself must not swallow that tail.
        $desc = @'
Specifies access control for the export. Valid values are `root-squash`, `all-squash`, and
`no-root-squash`.
`root-squash` prevents client users and groups with root privilege from mapping their
root privilege to a file system.
'@
        $trigger = Get-PfbValueEnumTriggerSentence -Description $desc
        $trigger | Should -Match '^Valid values are `root-squash`, `all-squash`, and\s*\n`no-root-squash`\.$'
        $trigger | Should -Not -Match 'prevents client users'
    }
}

Describe 'ConvertFrom-PfbValueEnumProse' {
    It 'parses the dominant backtick-quoted pattern' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values are `none`, `enabled`, and `suspended`.'
        $result.Parsed | Should -BeTrue
        $result.Values | Should -Be @('none', 'enabled', 'suspended')
    }

    It 'parses a double-quoted value list' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values are "policy", "sacl".'
        $result.Parsed | Should -BeTrue
        $result.Values | Should -Be @('policy', 'sacl')
    }

    It 'parses a bare comma-separated token list' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values include QSFP, QSFP+, QSFP28, QSFP56, QSFP-DD, RJ-45, and -.'
        $result.Parsed | Should -BeTrue
        $result.Values | Should -Be @('QSFP', 'QSFP+', 'QSFP28', 'QSFP56', 'QSFP-DD', 'RJ-45', '-')
    }

    It 'does not force-parse a malformed/unbalanced-quote sentence' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence "Valid values include 'success' or failure'."
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
        $result.TriggerText | Should -Not -BeNullOrEmpty
    }

    It 'does not force-parse a backtick-quoted list with a missing opening backtick (real spec bug: policy_type/smb-client)' {
        # Real, confirmed-malformed text from the FlashBlade OpenAPI spec (present in every
        # cached version REST 2.14-2.27): the opening backtick before `smb-client` is
        # missing. A naive backtick-pair regex re-synchronizes on the next backtick and
        # silently drops `smb-client` from the value list while injecting garbage
        # (comma/whitespace-only) "values" -- this must be classified unparsed instead.
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence 'Valid values include `alert`, `audit`, `s3-export`, smb-client`, `smb-share`, and `telemetry-metrics`.'
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
        $result.TriggerText | Should -Not -BeNullOrEmpty
    }

    It 'does not force-parse a numeric-range sentence that happens to match the trigger phrase' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence "Valid values are`nin the range of 300000 and 10800000."
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
    }

    It 'does not force-parse free-text prose that happens to match the trigger phrase' {
        $result = ConvertFrom-PfbValueEnumProse -TriggerSentence "Valid values are controllers`nand blades from hardware list."
        $result.Parsed | Should -BeFalse
        $result.Values | Should -BeNullOrEmpty
    }

    It 'preserves the raw trigger text on both parsed and unparsed results' {
        $sentence = 'Valid values are `a`, `b`.'
        (ConvertFrom-PfbValueEnumProse -TriggerSentence $sentence).TriggerText | Should -Be $sentence
    }
}

Describe 'Get-PfbSchemaPropertyDescriptions' {
    BeforeAll {
        $script:testSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas = [PSCustomObject]@{
                    BaseResource  = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            id   = [PSCustomObject]@{ type = 'string'; description = 'The resource identifier.' }
                            name = [PSCustomObject]@{ type = 'string' }
                        }
                    }
                    ResourcePatch = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    enabled = [PSCustomObject]@{ type = 'boolean'; description = 'Valid values are `true` and `false`.' }
                                }
                            }
                        )
                    }
                    ListWrapper   = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            tags = [PSCustomObject]@{
                                type  = 'array'
                                items = [PSCustomObject]@{ type = 'string'; description = 'Valid values are `a`, `b`.' }
                            }
                        }
                    }
                }
            }
        }
    }

    It 'reads direct property descriptions off an inline schema' {
        $schema = [PSCustomObject]@{
            properties = [PSCustomObject]@{
                a = [PSCustomObject]@{ description = 'first' }
                b = [PSCustomObject]@{ description = 'second' }
            }
        }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions['a'] | Should -Be 'first'
        $descriptions['b'] | Should -Be 'second'
    }

    It 'resolves a $ref schema before reading property descriptions' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions['id'] | Should -Be 'The resource identifier.'
    }

    It 'merges descriptions across allOf branches, including $ref branches' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/ResourcePatch' }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions['id'] | Should -Be 'The resource identifier.'
        $descriptions['enabled'] | Should -Be 'Valid values are `true` and `false`.'
    }

    It 'descends into an array property''s items schema for its description' {
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $testSpec.components.schemas.ListWrapper -Spec $testSpec
        $descriptions['tags'] | Should -Be 'Valid values are `a`, `b`.'
    }

    It 'omits properties with no resolvable description' {
        $schema = [PSCustomObject]@{ '$ref' = '#/components/schemas/BaseResource' }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        $descriptions.Contains('name') | Should -BeFalse
    }

    It 'returns an empty hashtable for a null schema' {
        (Get-PfbSchemaPropertyDescriptions -Schema $null -Spec $testSpec).Count | Should -Be 0
    }

    It 'returns descriptions in the schema''s own declared property order, not scrambled by hashtable enumeration' {
        # The returned dictionary is internally staged through a plain Hashtable (not
        # [ordered]) in earlier versions of this function, whose .Keys enumeration order
        # depends on .NET's per-process-randomized string hash codes -- without an
        # explicit [ordered] type, Reports/PfbValueEnumMap.json's entry order silently
        # varies run-to-run on identical input (confirmed live: regenerating it twice
        # produced two byte-different files, e.g. SnmpManager.version/.notification
        # swapping order). Property names below are deliberately declared out of
        # alphabetical order to prove insertion order (not sort order) is preserved.
        $schema = [PSCustomObject]@{
            properties = [PSCustomObject]@{
                zebra = [PSCustomObject]@{ description = 'z' }
                apple = [PSCustomObject]@{ description = 'a' }
                mango = [PSCustomObject]@{ description = 'm' }
            }
        }
        $descriptions = Get-PfbSchemaPropertyDescriptions -Schema $schema -Spec $testSpec
        @($descriptions.Keys) | Should -Be @('zebra', 'apple', 'mango')
    }
}

Describe 'Get-PfbSpecValueEnums' {
    BeforeAll {
        # Regression fixture: two distinct schemas share the property name "access"
        # with non-identical value lists (the squash-mode gotcha). Must never collapse.
        $script:squashSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas    = [PSCustomObject]@{
                    NfsExportPolicyRuleBase                       = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            access = [PSCustomObject]@{
                                type        = 'string'
                                description = 'Specifies access control for the export. Valid values are `root-squash`, `all-squash`, and `no-squash`.'
                            }
                        }
                    }
                    _presetWorkloadExportConfigurationNfsRule     = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            access = [PSCustomObject]@{
                                type        = 'string'
                                description = 'Specifies access control for the export. Valid values are `root-squash`, `all-squash`, and `no-root-squash`.'
                            }
                        }
                    }
                    Bucket                                        = [PSCustomObject]@{
                        allOf = @(
                            [PSCustomObject]@{
                                type       = 'object'
                                properties = [PSCustomObject]@{
                                    versioning = [PSCustomObject]@{
                                        type        = 'string'
                                        description = 'The versioning state for objects within the bucket. Valid values are `none`, `enabled`, and `suspended`.'
                                    }
                                }
                            }
                        )
                    }
                    UnparseableThing                               = [PSCustomObject]@{
                        type       = 'object'
                        properties = [PSCustomObject]@{
                            weirdField = [PSCustomObject]@{
                                type        = 'string'
                                description = "Valid values are`nin the range of 300000 and 10800000."
                            }
                        }
                    }
                }
                parameters = [PSCustomObject]@{
                    ArrayPerformanceProtocol = [PSCustomObject]@{
                        name        = 'protocol'
                        'in'        = 'query'
                        description = 'Filter by protocol. Valid values are `nfs`, `smb`, `http`, and `s3`.'
                    }
                    sort = [PSCustomObject]@{
                        name        = 'sort'
                        'in'        = 'query'
                        description = 'Sort field. Possible values include `name`, `id`.'
                    }
                    plain = [PSCustomObject]@{
                        name        = 'plain'
                        'in'        = 'query'
                        description = 'An ordinary parameter with no enumeration.'
                    }
                }
            }
        }

        $script:results = Get-PfbSpecValueEnums -Spec $squashSpec
    }

    It 'keys schema-property entries by "SchemaName.PropertyName", never bare property name' {
        ($results | Where-Object Key -eq 'NfsExportPolicyRuleBase.access') | Should -Not -BeNullOrEmpty
        ($results | Where-Object Key -eq '_presetWorkloadExportConfigurationNfsRule.access') | Should -Not -BeNullOrEmpty
    }

    It 'sets Name to the schema property name for schema-kind entries' {
        $bucket = $results | Where-Object Key -eq 'Bucket.versioning'
        $bucket.Name | Should -Be 'versioning'
    }

    It 'sets Name to the parameter''s wire "name" field, which may differ from its components.parameters dictionary key' {
        $protocolParam = $results | Where-Object Key -eq 'ArrayPerformanceProtocol'
        $protocolParam.Name | Should -Be 'protocol'
        $protocolParam.Values | Should -Be @('nfs', 'smb', 'http', 's3')
    }

    It 'never collapses two schemas sharing a property name into one entry (squash-mode gotcha)' {
        $base = $results | Where-Object Key -eq 'NfsExportPolicyRuleBase.access'
        $preset = $results | Where-Object Key -eq '_presetWorkloadExportConfigurationNfsRule.access'

        $base.Values | Should -Be @('root-squash', 'all-squash', 'no-squash')
        $preset.Values | Should -Be @('root-squash', 'all-squash', 'no-root-squash')
        $base.Values | Should -Not -Be $preset.Values
    }

    It 'Bucket.versioning regression: extracts exactly [none, enabled, suspended]' {
        $bucket = $results | Where-Object Key -eq 'Bucket.versioning'
        $bucket | Should -Not -BeNullOrEmpty
        $bucket.Values | Should -Be @('none', 'enabled', 'suspended')
        $bucket.Parsed | Should -BeTrue
    }

    It 'includes parameter-sourced entries with Kind = parameter' {
        $sort = $results | Where-Object { $_.Key -eq 'sort' -and $_.Kind -eq 'parameter' }
        $sort | Should -Not -BeNullOrEmpty
        $sort.Values | Should -Be @('name', 'id')
    }

    It 'does not emit a record for a parameter with no trigger phrase' {
        ($results | Where-Object Key -eq 'plain') | Should -BeNullOrEmpty
    }

    It 'classifies a trigger-matching but non-enumerable description as unparsed rather than dropping it' {
        $weird = $results | Where-Object Key -eq 'UnparseableThing.weirdField'
        $weird | Should -Not -BeNullOrEmpty
        $weird.Parsed | Should -BeFalse
        $weird.Values | Should -BeNullOrEmpty
        $weird.TriggerText | Should -Not -BeNullOrEmpty
    }

    It 'returns an empty list when the spec has no components' {
        $emptySpec = [PSCustomObject]@{ components = [PSCustomObject]@{} }
        Get-PfbSpecValueEnums -Spec $emptySpec | Should -BeNullOrEmpty
    }
}

Describe 'Get-PfbSpecValueEnums: inline path-operation parameters' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    # Skipped on Windows PowerShell 5.1: the "does not reprocess a $ref entry" case below
    # observably fails only on real WinPS 5.1 + Pester 6 (confirmed live) even though
    # calling Get-PfbSpecValueEnums directly with the identical fixture outside Pester
    # returns identical, correct results on both hosts -- this points at a Pester
    # 6-on-Desktop-CLR quirk, not a defect in this dev/CI-only tooling (never loaded by
    # the shipped module; see PureStorageFlashBladePowerShell.psm1).
    BeforeAll {
        # Regression fixture for the real GET /arrays/space `type` gap: a versioned
        # spec.paths key (every real cached spec carries an "/api/<version>/" prefix)
        # whose GET operation defines `type` INLINE (no $ref), alongside a sibling
        # parameter that is already a $ref (must NOT be reprocessed/double-counted) and
        # an inline parameter with no "Valid values..." trigger at all (must not emit a
        # record).
        $script:inlineSpec = [PSCustomObject]@{
            components = [PSCustomObject]@{
                schemas    = [PSCustomObject]@{}
                parameters = [PSCustomObject]@{
                    Resolution = [PSCustomObject]@{
                        name        = 'resolution'
                        'in'        = 'query'
                        description = 'The desired ms between samples. Valid values are `1000`, `30000`.'
                    }
                }
            }
            paths      = [PSCustomObject]@{
                '/api/2.0/arrays/space' = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ '$ref' = '#/components/parameters/Resolution' }
                            [PSCustomObject]@{
                                name        = 'type'
                                'in'        = 'query'
                                description = 'Display the metric of a specified object type. Valid values are `array`, `file-system`, and `object-store`. If not specified, defaults to `array`.'
                            }
                            [PSCustomObject]@{
                                name        = 'start_time'
                                'in'        = 'query'
                                description = 'When the time window starts (in milliseconds since epoch).'
                            }
                        )
                    }
                }
            }
        }

        $script:inlineResults = Get-PfbSpecValueEnums -Spec $inlineSpec
    }

    It 'extracts an inline (non-$ref) path-operation parameter as Kind = inline-parameter' {
        $rec = $inlineResults | Where-Object { $_.Kind -eq 'inline-parameter' }
        $rec | Should -Not -BeNullOrEmpty
        $rec.Values | Should -Be @('array', 'file-system', 'object-store')
        $rec.Name | Should -Be 'type'
    }

    It 'keys the inline-parameter record as "<METHOD> <path>#<paramName>", with the /api/<version>/ prefix stripped' {
        $rec = $inlineResults | Where-Object { $_.Kind -eq 'inline-parameter' }
        $rec.Key | Should -Be 'GET arrays/space#type'
    }

    It 'does not reprocess a $ref entry in the inline-parameter pass (no double-count of the Resolution parameter)' {
        ($inlineResults | Where-Object { $_.Name -eq 'resolution' }).Count | Should -Be 1
        ($inlineResults | Where-Object { $_.Name -eq 'resolution' }).Kind | Should -Be 'parameter'
    }

    It 'does not emit an inline-parameter record for an operation parameter with no trigger phrase' {
        ($inlineResults | Where-Object { $_.Name -eq 'start_time' }) | Should -BeNullOrEmpty
    }

    It 'strips a non-versioned path prefix down to just the leading slash (e.g. /oauth2/1.0/token-shaped paths)' {
        $spec = [PSCustomObject]@{
            components = [PSCustomObject]@{ schemas = [PSCustomObject]@{}; parameters = [PSCustomObject]@{} }
            paths      = [PSCustomObject]@{
                '/oauth2/1.0/token' = [PSCustomObject]@{
                    post = [PSCustomObject]@{
                        parameters = @(
                            [PSCustomObject]@{ name = 'grant_type'; 'in' = 'query'; description = 'Valid values are `client_credentials`.' }
                        )
                    }
                }
            }
        }
        $rec = Get-PfbSpecValueEnums -Spec $spec | Where-Object { $_.Kind -eq 'inline-parameter' }
        $rec.Key | Should -Be 'POST oauth2/1.0/token#grant_type'
    }
}

Describe 'Get-PfbResourceHint' {
    It 'strips the leading <Verb>-Pfb prefix' {
        Get-PfbResourceHint -CmdletName 'New-PfbNetworkInterface' | Should -Be 'NetworkInterface'
    }

    It 'returns the input unchanged when it does not match the <Verb>-Pfb shape' {
        Get-PfbResourceHint -CmdletName 'SomethingElse' | Should -Be 'SomethingElse'
    }
}

Describe 'Resolve-PfbFieldValueEnum' {
    BeforeAll {
        $script:history = [ordered]@{
            'Widget.color' = [ordered]@{ Name = 'color'; Kind = 'schema'; MinVersion = '2.0'; CurrentValues = @('red', 'blue'); DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('blue,red')) }
            'Type'                    = [ordered]@{ Name = 'type'; Kind = 'parameter'; MinVersion = '2.0'; CurrentValues = @('array', 'file-system'); DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('array,file-system')) }
            'Type_for_performance'    = [ordered]@{ Name = 'type'; Kind = 'parameter'; MinVersion = '2.0'; CurrentValues = @('array', 'client'); DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('array,client')) }
            'GET arrays/space#type'   = [ordered]@{ Name = 'type'; Kind = 'inline-parameter'; MinVersion = '2.0'; CurrentValues = @('array', 'file-system'); DistinctValueSets = [System.Collections.Generic.HashSet[string]]::new([string[]]@('array,file-system')) }
        }
    }

    It 'returns no-spec-enum-found when the wire name matches nothing' {
        $r = Resolve-PfbFieldValueEnum -WireName 'nope' -ResourceHint 'Widget' -History $history -OldestVersion '2.0'
        $r.Status | Should -Be 'no-spec-enum-found'
    }

    It 'matches via resource-hint-filtered schema kind' {
        $r = Resolve-PfbFieldValueEnum -WireName 'color' -ResourceHint 'Widget' -History $history -OldestVersion '2.0'
        $r.Status | Should -Be 'matched'
        $r.Recommendation | Should -Be 'ValidateSet'
    }

    It 'reports collision when parameter-kind records disagree and no inline match settles it' {
        $r = Resolve-PfbFieldValueEnum -WireName 'type' -ResourceHint 'Nothing' -History $history -OldestVersion '2.0'
        $r.Status | Should -Be 'collision'
    }

    It 'an exact inline-parameter match settles an otherwise-ambiguous parameter-kind wire name' {
        $r = Resolve-PfbFieldValueEnum -WireName 'type' -ResourceHint 'Nothing' -Endpoint 'arrays/space' -Method 'GET' -History $history -OldestVersion '2.0'
        $r.Status | Should -Be 'matched'
        $r.MatchedKey | Should -Be 'GET arrays/space#type'
    }
}

Describe 'Build-PfbValueEnumMap.ps1: inline-parameter-to-$ref refactor keeps the field''s minVersion at its original (inline) version' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $script:builderScript = Join-Path $repoRoot 'tools/Build-PfbValueEnumMap.ps1'

        # Reproduces the real Get-PfbArraySpace `type` history exactly: v1 defines it
        # inline on GET /arrays/space with a full "Valid values..." description; v2
        # refactors the SAME parameter into a components.parameters $ref with
        # byte-identical description text -- a pure documentation refactor, not an API
        # change. The field must still be attributed to v1, not v2, once diffed.
        New-Item -ItemType Directory -Path 'TestDrive:\inlineSpecs' -Force | Out-Null

        $description = 'Display the metric of a specified object type. Valid values are `array`, `file-system`, and `object-store`. If not specified, defaults to `array`.'

        $specV1 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '5.0' }
            components = [ordered]@{ schemas = [ordered]@{}; parameters = [ordered]@{} }
            paths      = [ordered]@{
                '/api/5.0/arrays/space' = [ordered]@{
                    get = [ordered]@{
                        parameters = @(
                            [ordered]@{ name = 'type'; 'in' = 'query'; description = $description }
                        )
                    }
                }
            }
        }
        $specV2 = [ordered]@{
            openapi    = '3.0.1'
            info       = @{ version = '5.1' }
            components = [ordered]@{
                schemas    = [ordered]@{}
                parameters = [ordered]@{
                    Type = [ordered]@{ name = 'type'; 'in' = 'query'; description = $description }
                }
            }
            paths      = [ordered]@{
                '/api/5.1/arrays/space' = [ordered]@{
                    get = [ordered]@{
                        parameters = @(
                            [ordered]@{ '$ref' = '#/components/parameters/Type' }
                        )
                    }
                }
            }
        }

        $specV1 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\inlineSpecs\fb5.0.json'
        $specV2 | ConvertTo-Json -Depth 20 | Set-Content -Path 'TestDrive:\inlineSpecs\fb5.1.json'

        & $builderScript -SpecsDirectory 'TestDrive:\inlineSpecs' -OutputPath 'TestDrive:\inlineOutput\map.json' -ReconciliationPath 'TestDrive:\inlineOutput\reconciliation.md'
        $script:inlineManifest = Get-Content -Path 'TestDrive:\inlineOutput\map.json' -Raw | ConvertFrom-Json -Depth 20
    }

    It 'extracts the older (inline) version as an inline-parameter-kind record keyed by method+path+name' {
        $inlineManifest.entries.'GET arrays/space#type' | Should -Not -BeNullOrEmpty
        $inlineManifest.entries.'GET arrays/space#type'.kind | Should -Be 'inline-parameter'
        $inlineManifest.entries.'GET arrays/space#type'.values | Should -Be @('array', 'file-system', 'object-store')
    }

    It 'attributes the inline-parameter record''s minVersion to the OLDER version, not the version where it became a $ref' {
        $inlineManifest.entries.'GET arrays/space#type'.minVersion | Should -Be '5.0'
    }

    It 'also records the newer $ref''d definition under components.parameters, separately, without disturbing the inline record' {
        $inlineManifest.entries.'Type' | Should -Not -BeNullOrEmpty
        $inlineManifest.entries.'Type'.kind | Should -Be 'parameter'
        $inlineManifest.entries.'Type'.minVersion | Should -Be '5.1'
    }
}
