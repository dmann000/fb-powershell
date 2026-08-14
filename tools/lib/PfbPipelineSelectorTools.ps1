#Requires -Version 5.1
<#
.SYNOPSIS
    Analysis layer for the issue #90 pipeline-selector audit: reflection inventory,
    producer resolution, candidate predicate, probe construction, outcome classification.
.DESCRIPTION
    Pure functions only. Nothing here imports the shipped module's HTTP path or invokes a
    cmdlet -- that is tools/lib/PfbSelectorProbeHarness.ps1's job, deliberately kept in its
    own file so the function-table mutation it performs stays small and auditable.
#>

function Get-PfbPipelineBoundParameter {
    <#
    .SYNOPSIS
        Every parameter across -Module that declares any pipeline binding.
    .DESCRIPTION
        Reflection, not AST, because reflection is what the engine itself binds on -- and
        because this module declares parameters in the bare attribute form
        [Parameter(ParameterSetName = 'ByName', ValueFromPipeline,
        ValueFromPipelineByPropertyName)], for which a regex expecting `= $true` matches
        zero of the 544 exported functions.
    .OUTPUTS
        [PSCustomObject]@{ Cmdlet; Verb; Parameter; ParameterType; Aliases;
        ValueFromPipeline; ValueFromPipelineByPropertyName; ParameterSets }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSModuleInfo]$Module
    )

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($command in (Get-Command -Module $Module.Name -CommandType Function)) {
        foreach ($parameter in $command.Parameters.Values) {
            $parameterAttributes = @($parameter.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })

            $fromPipeline = [bool]@($parameterAttributes | Where-Object { $_.ValueFromPipeline }).Count
            $fromProperty = [bool]@($parameterAttributes | Where-Object { $_.ValueFromPipelineByPropertyName }).Count
            if (-not ($fromPipeline -or $fromProperty)) { continue }

            $results.Add([PSCustomObject]@{
                    Cmdlet                          = $command.Name
                    Verb                            = ($command.Name -split '-')[0]
                    Parameter                       = $parameter.Name
                    ParameterType                   = $parameter.ParameterType.Name
                    Aliases                         = @($parameter.Aliases)
                    ValueFromPipeline               = $fromPipeline
                    ValueFromPipelineByPropertyName = $fromProperty
                    ParameterSets                   = @($parameterAttributes |
                            ForEach-Object { $_.ParameterSetName } | Sort-Object -Unique)
                })
        }
    }

    # Sorted at emit, invariant culture -- the same determinism rule the rest of tools/lib
    # follows (issue #85), so a Linux runner and a Windows workstation agree byte for byte.
    return @($results | Sort-Object -Property Cmdlet, Parameter -Culture '')
}
