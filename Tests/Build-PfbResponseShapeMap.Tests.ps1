BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:BuilderPath = Join-Path $script:RepoRoot 'tools/Build-PfbResponseShapeMap.ps1'

    function New-ShapeSpecFixture {
        param(
            [Parameter(Mandatory)][string[]]$EnvelopeProperties,
            [Parameter(Mandatory)][string[]]$ItemProperties
        )
        $envProps = [PSCustomObject]@{}
        foreach ($p in $EnvelopeProperties) {
            if ($p -eq 'items') { continue }
            $envProps | Add-Member -NotePropertyName $p -NotePropertyValue ([PSCustomObject]@{ type = 'integer' })
        }
        $itemProps = [PSCustomObject]@{}
        foreach ($p in $ItemProperties) {
            $itemProps | Add-Member -NotePropertyName $p -NotePropertyValue ([PSCustomObject]@{ type = 'string' })
        }
        $envProps | Add-Member -NotePropertyName 'items' -NotePropertyValue ([PSCustomObject]@{
                type = 'array'; items = [PSCustomObject]@{ properties = $itemProps }
            })

        [PSCustomObject]@{
            paths = [PSCustomObject]@{
                '/api/2.0/widgets' = [PSCustomObject]@{
                    get = [PSCustomObject]@{
                        responses = [PSCustomObject]@{
                            '200' = [PSCustomObject]@{
                                content = [PSCustomObject]@{
                                    'application/json' = [PSCustomObject]@{ schema = [PSCustomObject]@{ properties = $envProps } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # Same response node as above, but lets several paths be declared in a CHOSEN order within
    # one spec, so emission order can be asserted against insertion order.
    function New-MultiPathShapeSpecFixture {
        param(
            # Ordered array of [PSCustomObject]@{ Path; EnvelopeProperties; ItemProperties }
            [Parameter(Mandatory)][object[]]$Endpoints
        )
        $paths = [PSCustomObject]@{}
        foreach ($ep in $Endpoints) {
            $single = New-ShapeSpecFixture -EnvelopeProperties $ep.EnvelopeProperties -ItemProperties $ep.ItemProperties
            $paths | Add-Member -NotePropertyName $ep.Path -NotePropertyValue $single.paths.'/api/2.0/widgets'
        }
        [PSCustomObject]@{ paths = $paths }
    }
}

Describe 'Build-PfbResponseShapeMap' -Skip:($PSVersionTable.PSVersion.Major -lt 7) {
    It 'records first-seen introducedVersion for fields present throughout' {
        $specs = Join-Path $TestDrive 'specs'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name', 'added_later') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.1.json')

        $out = Join-Path $TestDrive 'map.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        $ep = $map.endpoints.'GET /widgets'
        $ep.responseItemProperties.name | Should -Be '9.0'
        $ep.responseItemProperties.added_later | Should -Be '9.1'
        $ep.minVersion | Should -Be '9.0'
        $ep.lastSeenVersion | Should -Be '9.1'
    }

    It 'moves a field that disappears into removedResponseFields, not responseItemProperties' {
        $specs = Join-Path $TestDrive 'specs2'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name', 'copyable') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.1.json')

        $out = Join-Path $TestDrive 'map2.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        $ep = $map.endpoints.'GET /widgets'
        $ep.responseItemProperties.PSObject.Properties.Name | Should -Not -Contain 'copyable'
        @($ep.removedResponseFields).Count | Should -Be 1
        $ep.removedResponseFields[0].field | Should -Be 'copyable'
        $ep.removedResponseFields[0].location | Should -Be 'items'
        $ep.removedResponseFields[0].introducedVersion | Should -Be '9.0'
        $ep.removedResponseFields[0].lastSeenVersion | Should -Be '9.0'
    }

    It 'detects envelope-level removal too' {
        $specs = Join-Path $TestDrive 'specs3'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items', 'total_item_count') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.1.json')

        $out = Join-Path $TestDrive 'map3.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        $removed = @($map.endpoints.'GET /widgets'.removedResponseFields)
        $removed.Count | Should -Be 1
        $removed[0].field | Should -Be 'total_item_count'
        $removed[0].location | Should -Be 'envelope'
    }

    It 'omits removedResponseFields entirely when nothing was removed' {
        $specs = Join-Path $TestDrive 'specs4'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')

        $out = Join-Path $TestDrive 'map4.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        $map.endpoints.'GET /widgets'.PSObject.Properties.Name | Should -Not -Contain 'removedResponseFields'
    }

    It 'sorts versions numerically, not lexically (9.9 before 9.10)' {
        $specs = Join-Path $TestDrive 'specs5'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.9.json')
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name', 'newer') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.10.json')

        $out = Join-Path $TestDrive 'map5.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        $map.generatedFrom[-1] | Should -Be '9.10'
        # 'newer' appears only in 9.10; if sorting were lexical, 9.10 would be processed
        # first and 'newer' would be recorded as removed.
        $map.endpoints.'GET /widgets'.responseItemProperties.newer | Should -Be '9.10'
        $map.endpoints.'GET /widgets'.PSObject.Properties.Name | Should -Not -Contain 'removedResponseFields'
    }

    It 'is deterministic across two runs' {
        $specs = Join-Path $TestDrive 'specs6'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items', 'errors') -ItemProperties @('name', 'id', 'created') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')

        $a = Join-Path $TestDrive 'runA.json'
        $b = Join-Path $TestDrive 'runB.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $a | Out-Null
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $b | Out-Null

        (Get-FileHash $a -Algorithm SHA256).Hash | Should -Be (Get-FileHash $b -Algorithm SHA256).Hash
    }

    It 'emits endpoint keys and field names in sorted order, not insertion order' {
        # Dictionary<T> enumeration is stable for a fixed insertion sequence, so a
        # two-runs-hash-equal check passes even with every Sort-Object deleted. This asserts the
        # literal emitted order instead. Both fixtures declare paths zebras-before-alphas, and
        # 'alpha' is introduced at 9.1 AFTER 'mango'/'zebra' were inserted at 9.0 -- so without
        # sorting the emission would be zebras-then-alphas and mango,zebra,alpha.
        $specs = Join-Path $TestDrive 'specs8'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-MultiPathShapeSpecFixture -Endpoints @(
            [PSCustomObject]@{ Path = '/api/2.0/zebras'; EnvelopeProperties = @('items'); ItemProperties = @('mango', 'zebra') }
            [PSCustomObject]@{ Path = '/api/2.0/alphas'; EnvelopeProperties = @('items'); ItemProperties = @('name') }
        ) | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')
        New-MultiPathShapeSpecFixture -Endpoints @(
            [PSCustomObject]@{ Path = '/api/2.0/zebras'; EnvelopeProperties = @('items'); ItemProperties = @('mango', 'zebra', 'alpha') }
            [PSCustomObject]@{ Path = '/api/2.0/alphas'; EnvelopeProperties = @('items'); ItemProperties = @('name') }
        ) | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.1.json')

        $out = Join-Path $TestDrive 'map8.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        @($map.endpoints.PSObject.Properties.Name) | Should -Be @('GET /alphas', 'GET /zebras')
        @($map.endpoints.'GET /zebras'.responseItemProperties.PSObject.Properties.Name) |
            Should -Be @('alpha', 'mango', 'zebra')
    }

    It 'throws rather than emitting an empty map when no spec filename parses' {
        $specs = Join-Path $TestDrive 'specs9'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        # Matches the fb*.json glob but not the fb<major>.<minor> version regex.
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('name') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fbXYZ.json')

        $out = Join-Path $TestDrive 'map9.json'
        { & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out -WarningAction SilentlyContinue } |
            Should -Throw -ExpectedMessage '*parseable*'
        Test-Path $out | Should -BeFalse
    }

    It 'does not let an API field named "keys" shadow dictionary members' {
        $specs = Join-Path $TestDrive 'specs7'; New-Item -ItemType Directory -Path $specs -Force | Out-Null
        New-ShapeSpecFixture -EnvelopeProperties @('items') -ItemProperties @('keys', 'count', 'values') |
            ConvertTo-Json -Depth 20 | Set-Content (Join-Path $specs 'fb9.0.json')

        $out = Join-Path $TestDrive 'map7.json'
        & $script:BuilderPath -SpecsDirectory $specs -OutputPath $out | Out-Null

        $map = Get-Content $out -Raw | ConvertFrom-Json
        $names = $map.endpoints.'GET /widgets'.responseItemProperties.PSObject.Properties.Name
        $names | Should -Contain 'keys'
        $names | Should -Contain 'count'
        $names | Should -Contain 'values'
    }
}
