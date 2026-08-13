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
