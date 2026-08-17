<#
    Accepted pipeline-selector findings for issue #90 -- the debt register Rail A enforces.

    Rail A (Tests/PfbPipelineSelectorRail.Tests.ps1) re-probes every pair in
    Reports/PfbPipelineSelectorMap.json and fails on any Coerced or WrongScalar selector not
    listed here. It also fails on a waiver whose pair no longer coerces, so a fix must delete
    its waiver rather than leave a licence behind for the next reintroduction.

    ONE ENTRY PER (Cmdlet, Parameter) PAIR, NOT PER PRODUCING ENDPOINT. The current report's
    268 finding rows are producer multiplicity over 102 real defects; keying by triple would be
    268 entries against psd1's hard 500-element cap for a single collection literal, and would
    list the same defect up to a dozen times. (The pre-fix audit measured 389 rows over 127
    pairs; the guards and renames delivered for #90 account for the reduction.)

    Scope and Producers are LOAD-BEARING, not annotation -- pair-level keying is otherwise
    blind to where a coercion happens. Rail A fails if a Family-scoped waiver's pair starts
    coercing on its PRIMARY producer (the chain a user would obviously write), and fails if a
    pair's producer count moves off the number the waiver was granted for. Keep both accurate.

    Fields: Cmdlet, Parameter, Scope (Primary = coerces against the cmdlet's own base-path GET;
    Family = only against another endpoint in the same resource family), Issue, Producers (how
    many endpoints reproduce it), Why.

    Issue is #90 for every entry because the fix issue does not exist yet -- #90 delivers the
    audit and this rail, and the split issue is filed after the PR exists. Re-pointing these at
    that issue is a follow-up commit.

    Clusters below are the audit report's root-cause clusters (issue-90-audit-report.md, 3.3),
    not cosmetic grouping: each cluster is one fix, not N.
#>
@{
    Waivers = @(

        # === Cluster 1 -- the rule/member family (1 pair still waived here, all on a PRIMARY
        # producer; the audit found 16 and the other 15 are now guarded or renamed).
        # The parent is returned as a nested object (policy, member, role), never as a flat
        # policy_name/member_name/role_name string, so a name-shaped selector can never bind by
        # property name. One API design decision repeated across roughly a dozen endpoint
        # families: fix it as one change, not sixteen.
        @{ Cmdlet = 'Get-PfbUserGroupQuotaPolicyRule';             Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /user-group-quota-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item. Waived rather than fixed because the array honours a policy_names key the published OpenAPI omits, and the published spec governs.' }

        # === Cluster 2 -- sub-resources that have no name at all (1 pair still waived here, all on
        # a PRIMARY producer; the audit found 10 and the other 9 had the dead parameter removed).
        # -Name is pipeline-bound on a resource whose items carry no name field. Dropping
        # ValueFromPipeline narrows the class but does not eliminate it: the four-pass finding
        # showed pass 4 is ByPropertyName WITH coercion, so an alias matching an object-valued
        # property still coerces with ValueFromPipeline absent. The two Remove-* pairs the audit
        # found here (Remove-PfbOpenFile, Remove-PfbResourceAccess, both since fixed by parameter
        # removal) were its highest-severity findings -- a DELETE whose selector is a stringified
        # object is where selects-the-wrong-thing and destructive intersect.
        @{ Cmdlet = 'Get-PfbArrayConnectionKey';                   Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /array-connections/connection-key items carry no name (connection_key, created, expires), yet -Name is pipeline-bound, so names receives the stringified item.' }

        # === Cluster 4 -- family-only exposure (100 pairs, NOT reachable from the primary producer).
        # Each cmdlet's own primary producer returns name correctly, so the obvious chain is
        # safe; other endpoints in the same family do not. Lower priority, and one guard fixes
        # the whole class at once. No .EXAMPLE chain the module documents produces any of these
        # -- every pipeline chain this module advertises works. "Family endpoints coerce" is a
        # count of PRODUCING ENDPOINTS for that pair; the named one is an example, and the
        # mechanism described belongs to it.
        @{ Cmdlet = 'Get-PfbActiveDirectory';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /active-directory/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbAdmin';                                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /admins/api-tokens -- its items carry no name (admin, api_token, context).' }
        @{ Cmdlet = 'Get-PfbAdminCache';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /admins/api-tokens -- its items carry no name (admin, api_token, context).' }
        @{ Cmdlet = 'Get-PfbAlertWatcher';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /alert-watchers/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbAuditFileSystemPolicy';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /audit-file-systems-policies/members -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbAuditObjectStorePolicy';               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /audit-object-store-policies/members -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificate';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /certificates/certificate-groups -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificateGroup';                     Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /certificate-groups/certificates -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificateGroupUse';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /certificate-groups/certificates -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificateUse';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /certificates/certificate-groups -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbDataEvictionPolicy';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /data-eviction-policies/file-systems -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbDirectoryService';                     Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /directory-services/local/groups/members -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbDirectoryServiceRole';                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /directory-services/local/groups/members -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbFileLock';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileLockClient';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystem';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemGroupPerformance';           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemSession';                    Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemSnapshot';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /file-system-snapshots/policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemSnapshotTransfer';           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /file-system-snapshots/policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemStorageClass';               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemUserPerformance';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFleet';                                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /fleets/fleet-key -- its items carry no name (created, expires, fleet_key).' }
        @{ Cmdlet = 'Get-PfbKmip';                                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /kmip/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbLegalHold';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /legal-holds/held-entities -- its items carry no name (file_system, legal_hold, path, status).' }
        @{ Cmdlet = 'Get-PfbLocalDirectoryService';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /directory-services/local/groups/members -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbLocalGroup';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /directory-services/local/groups/members -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbManagementAccessPolicy';               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; 3 family endpoints coerce, e.g. GET /management-access-policies/admins -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbNetworkAccessPolicy';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /network-access-policies/members -- that join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbNetworkInterface';                     Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /network-interfaces/neighbors -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceConnector';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /network-interfaces/neighbors -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceConnectorPerformance'; Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /network-interfaces/neighbors -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceConnectorSettings';    Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /network-interfaces/neighbors -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNodeGroup';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /node-groups/nodes -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbNodeGroupUse';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /node-groups/nodes -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbObjectStoreAccessPolicy';              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /object-store-access-policies/object-store-roles -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbObjectStoreRole';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-roles/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbObjectStoreUser';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-users/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbOidcIdp';                              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /sso/saml2/idps/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbPolicy';                               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /policies/file-system-replica-links -- that join item returns its endpoints as objects (context, link, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbPolicyAll';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /policies-all/members -- that join item returns its endpoints as objects (context, link, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbQosPolicy';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; 3 family endpoints coerce, e.g. GET /qos-policies/buckets -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbRealm';                                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /realms/defaults -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Get-PfbRealmSpace';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /realms/defaults -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Get-PfbRealmStorageClass';                    Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /realms/defaults -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Get-PfbResiliencyGroup';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /resiliency-groups/members -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbSaml2Idp';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /sso/saml2/idps/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbSnmpManager';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /snmp-managers/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbSshCaPolicy';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; 3 family endpoints coerce, e.g. GET /ssh-certificate-authority-policies/admins -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbStorageClassTieringPolicy';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /storage-class-tiering-policies/members -- that join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbSupport';                              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /support/system-manifest -- its items carry no name (context, system-manifest).' }
        @{ Cmdlet = 'Get-PfbSupportDiagnostics';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /support-diagnostics/settings -- its items carry no name (last_updated, version).' }
        @{ Cmdlet = 'Get-PfbSupportDiagnosticsDetails';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /support-diagnostics/settings -- its items carry no name (last_updated, version).' }
        @{ Cmdlet = 'Get-PfbSyslogServer';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /syslog-servers/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbTlsPolicy';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /tls-policies/members -- that join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbWorkload';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /workloads/tags -- its items carry no name (context, copyable, key, namespace, resource, value).' }
        @{ Cmdlet = 'Get-PfbWormPolicy';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /worm-data-policies/members -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbActiveDirectory';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /active-directory/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbAdminCache';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /admins/api-tokens -- its items carry no name (admin, api_token, context).' }
        @{ Cmdlet = 'Remove-PfbAlertWatcher';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /alert-watchers/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbAuditFileSystemPolicy';             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /audit-file-systems-policies/members -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbAuditObjectStorePolicy';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /audit-object-store-policies/members -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbCertificate';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /certificates/certificate-groups -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbCertificateGroup';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /certificate-groups/certificates -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbDataEvictionPolicy';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /data-eviction-policies/file-systems -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbDirectoryServiceRole';              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /directory-services/local/groups/members -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Remove-PfbFileLock';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystem';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystemSession';                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; 9 family endpoints coerce, e.g. GET /file-systems/audit-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystemSnapshot';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /file-system-snapshots/policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer';        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /file-system-snapshots/policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFleet';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /fleets/fleet-key -- its items carry no name (created, expires, fleet_key).' }
        @{ Cmdlet = 'Remove-PfbLegalHold';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /legal-holds/held-entities -- its items carry no name (file_system, legal_hold, path, status).' }
        @{ Cmdlet = 'Remove-PfbLocalGroup';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /directory-services/local/groups/members -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Remove-PfbManagementAccessPolicy';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; 3 family endpoints coerce, e.g. GET /management-access-policies/admins -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbNetworkAccessRule';                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /network-access-policies/members -- that join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbNetworkInterface';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; 5 family endpoints coerce, e.g. GET /network-interfaces/neighbors -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Remove-PfbNodeGroup';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /node-groups/nodes -- that join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreAccessPolicy';           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /object-store-access-policies/object-store-roles -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreAccessPolicyRule';       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /object-store-access-policies/object-store-roles -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreRole';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-roles/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreTrustPolicyRule';        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-roles/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreUser';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-users/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbOidcIdp';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /sso/saml2/idps/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbPolicy';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; 4 family endpoints coerce, e.g. GET /policies/file-system-replica-links -- that join item returns its endpoints as objects (context, link, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbQosPolicy';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; 3 family endpoints coerce, e.g. GET /qos-policies/buckets -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbRealm';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /realms/defaults -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Remove-PfbSaml2Idp';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /sso/saml2/idps/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbSnmpManager';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /snmp-managers/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbSshCaPolicy';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; 3 family endpoints coerce, e.g. GET /ssh-certificate-authority-policies/admins -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbStorageClassTieringPolicy';         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /storage-class-tiering-policies/members -- that join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbSyslogServer';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /syslog-servers/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbTlsPolicy';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /tls-policies/members -- that join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbUserGroupQuotaPolicy';              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /user-group-quota-policies/file-systems -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbWorkload';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /workloads/tags -- its items carry no name (context, copyable, key, namespace, resource, value).' }
        @{ Cmdlet = 'Remove-PfbWormPolicy';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /worm-data-policies/members -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Update-PfbKmip';                              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /kmip/test -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Update-PfbObjectStoreAccessPolicyRule';       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; 2 family endpoints coerce, e.g. GET /object-store-access-policies/object-store-roles -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Update-PfbObjectStoreRole';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-roles/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Update-PfbObjectStoreTrustPolicyRule';        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; one family endpoint coerces, GET /object-store-roles/object-store-access-policies -- that join item returns its endpoints as objects (context, member, policy) and carries no name.' }
    )
}
