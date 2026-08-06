# Fusion context parameter names, shared by the runtime injection path (Phase 1) and the
# maintainer drift check in tools/lib/PfbContextRuleTools.ps1.
#
# These live in Private/ rather than tools/ because tools/ may depend on Private/ and never
# the reverse -- the same dependency direction issue #74 exists to fix. tools/ dot-sources
# this file explicitly, since tools/ is not on the module's load path.
#
# The 'Context_names_get' component literal is deliberately NOT here: it is the cardinality
# rule's own business and already lives inside Test-PfbContextMultiValueCapable, which is
# THE single declared home of that rule. A second definition here would be exactly the
# duplication #74 is about.
$script:PfbContextParameterName     = 'context_names'
$script:PfbAllowErrorsParameterName = 'allow_errors'

# Fleet-scoped endpoints where a NAME-SCOPED read genuinely cannot resolve without a fleet
# context. Measured, not derived: GET /presets/workload?names=<a preset that exists> returns
# code 6 with no context and 200 with a fleet context, because the locally replicated view is
# list-only. The three fleet-scoped topology-group GETs are deliberately ABSENT -- a
# name-scoped context-free read returns 200 there, so throwing would reject a working call.
# Add an endpoint here only with a measurement; absent evidence, do not throw.
$script:PfbNameScopedContextRequiredEndpoints = @('GET /presets/workload')
