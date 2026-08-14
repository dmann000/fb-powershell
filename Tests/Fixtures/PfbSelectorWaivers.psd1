<#
    Accepted pipeline-selector findings for issue #90 -- the debt register Rail A enforces.

    Rail A (Tests/PfbPipelineSelectorRail.Tests.ps1) re-probes every pair in
    Reports/PfbPipelineSelectorMap.json and fails on any Coerced or WrongScalar selector not
    listed here. It also fails on a waiver whose pair no longer coerces, so a fix must delete
    its waiver rather than leave a licence behind for the next reintroduction.

    ONE ENTRY PER (Cmdlet, Parameter) PAIR, NOT PER PRODUCING ENDPOINT. The audit's 389
    finding rows are producer multiplicity over 127 real defects; keying by triple would be
    389 entries against psd1's hard 500-element cap for a single collection literal, and would
    list the same defect up to a dozen times. Producers records how many endpoints reproduce
    the pair; the rail names the specific endpoint in its failure text.

    Fields: Cmdlet, Parameter, Scope (Primary = reachable from the cmdlet's own base-path GET,
    the chain a user would obviously write; Family = only from another endpoint in the same
    resource family), Issue, Producers, Why.

    Issue is #90 for every entry because the fix issue does not exist yet -- #90 delivers the
    audit and this rail, and the split issue is filed after the PR exists. Re-pointing these at
    that issue is a follow-up commit.

    Clusters below are the audit report's root-cause clusters (issue-90-audit-report.md, 3.3),
    not cosmetic grouping: each cluster is one fix, not N.
#>
@{
    Waivers = @(

        # === Cluster 1 -- the rule/member family (16 pairs, all on a PRIMARY producer).
        # The parent is returned as a nested object (policy, member, role), never as a flat
        # policy_name/member_name/role_name string, so a name-shaped selector can never bind by
        # property name. One API design decision repeated across roughly a dozen endpoint
        # families: fix it as one change, not sixteen.
        @{ Cmdlet = 'Get-PfbBucketAccessPolicy';                   Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'GET /buckets/bucket-access-policies items carry no member/member_name field -- membership is a separate endpoint -- so member_names receives the stringified policy item.' }
        @{ Cmdlet = 'Get-PfbBucketAccessPolicyRule';               Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'GET /buckets/bucket-access-policies/rules items carry no member/member_name field -- membership is a separate endpoint -- so member_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbBucketAuditFilter';                    Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'GET /buckets/audit-filters items carry no member/member_name field -- membership is a separate endpoint -- so member_names receives the stringified filter item.' }
        @{ Cmdlet = 'Get-PfbBucketCorsPolicy';                     Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'GET /buckets/cross-origin-resource-sharing-policies items carry no member/member_name field -- membership is a separate endpoint -- so member_names receives the stringified policy item.' }
        @{ Cmdlet = 'Get-PfbBucketCorsPolicyRule';                 Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'GET /buckets/cross-origin-resource-sharing-policies/rules items carry no member/member_name field -- membership is a separate endpoint -- so member_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbNetworkAccessRule';                    Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 3
            Why = 'GET /network-access-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbNfsExportRule';                        Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 2
            Why = 'GET /nfs-export-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbObjectStoreAccessPolicyRule';          Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /object-store-access-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbObjectStoreTrustPolicy';               Parameter = 'RoleName';    Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /object-store-roles/object-store-trust-policies returns role as a nested object, never a flat role_name, so role_names receives the stringified policy item.' }
        @{ Cmdlet = 'Get-PfbObjectStoreTrustPolicyRule';           Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /object-store-roles/object-store-trust-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbS3ExportRule';                         Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 2
            Why = 'GET /s3-export-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbSmbClientRule';                        Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 2
            Why = 'GET /smb-client-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbSmbShareRule';                         Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 2
            Why = 'GET /smb-share-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Get-PfbUserGroupQuotaPolicyRule';             Parameter = 'PolicyName';  Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /user-group-quota-policies/rules returns policy as a nested object, never a flat policy_name, so policy_names receives the stringified rule item.' }
        @{ Cmdlet = 'Remove-PfbBucketAuditFilter';                 Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'DESTRUCTIVE -- GET /buckets/audit-filters items carry no member/member_name field, so a piped filter item lands in member_names of a DELETE as a stringified object.' }
        @{ Cmdlet = 'Remove-PfbBucketCorsPolicy';                  Parameter = 'MemberName';  Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'DESTRUCTIVE -- GET /buckets/cross-origin-resource-sharing-policies items carry no member/member_name field, so a piped policy item lands in member_names of a DELETE as a stringified object.' }

        # === Cluster 2 -- sub-resources that have no name at all (10 pairs, all on a PRIMARY producer).
        # -Name is pipeline-bound on a resource whose items carry no name field. Dropping
        # ValueFromPipeline eliminates the class outright: zero coercions occurred without it.
        # The four Remove-* pairs are the highest-severity findings in the audit -- a DELETE
        # whose selector is a stringified object is where selects-the-wrong-thing and
        # destructive intersect.
        @{ Cmdlet = 'Get-PfbArrayConnectionKey';                   Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 4
            Why = 'GET /array-connections/connection-key items carry no name (connection_key, created, expires), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbCertificateGroupCertificate';          Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 1
            Why = 'GET /certificate-groups/certificates items carry no name (group, member -- both objects), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbFleetKey';                             Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 2
            Why = 'GET /fleets/fleet-key items carry no name (created, expires, fleet_key), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbNetworkConnectionStatistics';          Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 5
            Why = 'GET /network-interfaces/network-connection-statistics items carry no name (current_state, local, remote, time), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceNeighbor';             Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 5
            Why = 'GET /network-interfaces/neighbors items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbOpenFile';                             Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 9
            Why = 'GET /file-systems/open-files items carry no name (client, id, lock_count, mode, path, session, source, user), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbRealmDefaults';                        Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 1
            Why = 'GET /realms/defaults items carry no name (context, object_store, realm), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Get-PfbResourceAccess';                       Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 1
            Why = 'GET /resource-accesses items carry no name (id, resource, scope), yet -Name is pipeline-bound, so names receives the stringified item.' }
        @{ Cmdlet = 'Remove-PfbOpenFile';                          Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 9
            Why = 'DESTRUCTIVE -- GET /file-systems/open-files items carry no name (client, id, lock_count, mode, path, session, source, user), so a piped open file lands in names of a DELETE as a stringified object.' }
        @{ Cmdlet = 'Remove-PfbResourceAccess';                    Parameter = 'Name';        Scope = 'Primary'; Issue = '#90'; Producers = 1
            Why = 'DESTRUCTIVE -- GET /resource-accesses items carry no name (id, resource, scope), so a piped access record lands in names of a DELETE as a stringified object.' }

        # === Cluster 3 -- a type mismatch on a name that does match (1 pair).
        # The field exists but is an object. This is also the audit control-leakage case.
        @{ Cmdlet = 'Get-PfbLocalGroupMember';                     Parameter = 'Group';       Scope = 'Primary'; Issue = '#90'; Producers = 8
            Why = 'GET /directory-services/local/groups/members returns group as an object, so -Group receives a stringified group rather than its name.' }

        # === Cluster 4 -- family-only exposure (100 pairs, NOT reachable from the primary producer).
        # Each cmdlet's own primary producer returns name correctly, so the obvious chain is
        # safe; another endpoint in the same family does not. Lower priority, and one guard
        # fixes the whole class at once. No .EXAMPLE chain the module documents produces any
        # of these -- every pipeline chain this module advertises works.
        @{ Cmdlet = 'Get-PfbActiveDirectory';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /active-directory/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbAdmin';                                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /admins/api-tokens coerces -- its items carry no name (admin, api_token, context).' }
        @{ Cmdlet = 'Get-PfbAdminCache';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /admins/api-tokens coerces -- its items carry no name (admin, api_token, context).' }
        @{ Cmdlet = 'Get-PfbAlertWatcher';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /alert-watchers/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbAuditFileSystemPolicy';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /audit-file-systems-policies/members coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbAuditObjectStorePolicy';               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /audit-object-store-policies/members coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificate';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /certificates/certificate-groups coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificateGroup';                     Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /certificate-groups/certificates coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificateGroupUse';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /certificate-groups/certificates coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbCertificateUse';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /certificates/certificate-groups coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbDataEvictionPolicy';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /data-eviction-policies/file-systems coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbDirectoryService';                     Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /directory-services/local/groups/members coerces -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbDirectoryServiceRole';                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /directory-services/local/groups/members coerces -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbFileLock';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileLockClient';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystem';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemGroupPerformance';           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemSession';                    Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemSnapshot';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-system-snapshots/policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemSnapshotTransfer';           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-system-snapshots/policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemStorageClass';               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFileSystemUserPerformance';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbFleet';                                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /fleets/fleet-key coerces -- its items carry no name (created, expires, fleet_key).' }
        @{ Cmdlet = 'Get-PfbKmip';                                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /kmip/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbLegalHold';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /legal-holds/held-entities coerces -- its items carry no name (file_system, legal_hold, path, status).' }
        @{ Cmdlet = 'Get-PfbLocalDirectoryService';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /directory-services/local/groups/members coerces -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbLocalGroup';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /directory-services/local/groups/members coerces -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Get-PfbManagementAccessPolicy';               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; only the family chain GET /management-access-policies/admins coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbNetworkAccessPolicy';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-access-policies/members coerces -- the join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbNetworkInterface';                     Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-interfaces/neighbors coerces -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceConnector';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-interfaces/neighbors coerces -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceConnectorPerformance'; Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-interfaces/neighbors coerces -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNetworkInterfaceConnectorSettings';    Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-interfaces/neighbors coerces -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Get-PfbNodeGroup';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /node-groups/nodes coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbNodeGroupUse';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /node-groups/nodes coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbObjectStoreAccessPolicy';              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-access-policies/object-store-roles coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbObjectStoreRole';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-roles/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbObjectStoreUser';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-users/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbOidcIdp';                              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /sso/saml2/idps/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbPolicy';                               Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /policies/file-system-replica-links coerces -- the join item returns its endpoints as objects (context, link, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbPolicyAll';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /policies-all/members coerces -- the join item returns its endpoints as objects (context, link, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbQosPolicy';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; only the family chain GET /qos-policies/buckets coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbRealm';                                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /realms/defaults coerces -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Get-PfbRealmSpace';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /realms/defaults coerces -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Get-PfbRealmStorageClass';                    Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /realms/defaults coerces -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Get-PfbResiliencyGroup';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /resiliency-groups/members coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Get-PfbSaml2Idp';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /sso/saml2/idps/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbSnmpManager';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /snmp-managers/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbSshCaPolicy';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; only the family chain GET /ssh-certificate-authority-policies/admins coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbStorageClassTieringPolicy';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /storage-class-tiering-policies/members coerces -- the join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbSupport';                              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /support/system-manifest coerces -- its items carry no name (context, system-manifest).' }
        @{ Cmdlet = 'Get-PfbSupportDiagnostics';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /support-diagnostics/settings coerces -- its items carry no name (last_updated, version).' }
        @{ Cmdlet = 'Get-PfbSupportDiagnosticsDetails';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /support-diagnostics/settings coerces -- its items carry no name (last_updated, version).' }
        @{ Cmdlet = 'Get-PfbSyslogServer';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /syslog-servers/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Get-PfbTlsPolicy';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /tls-policies/members coerces -- the join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Get-PfbWorkload';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /workloads/tags coerces -- its items carry no name (context, copyable, key, namespace, resource, value).' }
        @{ Cmdlet = 'Get-PfbWormPolicy';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /worm-data-policies/members coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbActiveDirectory';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /active-directory/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbAdminCache';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /admins/api-tokens coerces -- its items carry no name (admin, api_token, context).' }
        @{ Cmdlet = 'Remove-PfbAlertWatcher';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /alert-watchers/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbAuditFileSystemPolicy';             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /audit-file-systems-policies/members coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbAuditObjectStorePolicy';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /audit-object-store-policies/members coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbCertificate';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /certificates/certificate-groups coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbCertificateGroup';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /certificate-groups/certificates coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbDataEvictionPolicy';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /data-eviction-policies/file-systems coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbDirectoryServiceRole';              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /directory-services/local/groups/members coerces -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Remove-PfbFileLock';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystem';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystemSession';                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 9
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-systems/audit-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystemSnapshot';                Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-system-snapshots/policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFileSystemSnapshotTransfer';        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /file-system-snapshots/policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbFleet';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /fleets/fleet-key coerces -- its items carry no name (created, expires, fleet_key).' }
        @{ Cmdlet = 'Remove-PfbLegalHold';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /legal-holds/held-entities coerces -- its items carry no name (file_system, legal_hold, path, status).' }
        @{ Cmdlet = 'Remove-PfbLocalGroup';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /directory-services/local/groups/members coerces -- its items carry no name (context, group, group_gid, is_primary_group, local_directory_service, member, member_id, realms, server).' }
        @{ Cmdlet = 'Remove-PfbManagementAccessPolicy';            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; only the family chain GET /management-access-policies/admins coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbNetworkAccessRule';                 Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-access-policies/members coerces -- the join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbNetworkInterface';                  Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 5
            Why = 'Primary producer binds -Name correctly; only the family chain GET /network-interfaces/neighbors coerces -- its items carry no name (initial_ttl_in_sec, local_port, neighbor_chassis, neighbor_port).' }
        @{ Cmdlet = 'Remove-PfbNodeGroup';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /node-groups/nodes coerces -- the join item returns its endpoints as objects (group, member) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreAccessPolicy';           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-access-policies/object-store-roles coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreAccessPolicyRule';       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-access-policies/object-store-roles coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreRole';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-roles/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreTrustPolicyRule';        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-roles/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbObjectStoreUser';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-users/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbOidcIdp';                           Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /sso/saml2/idps/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbPolicy';                            Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 4
            Why = 'Primary producer binds -Name correctly; only the family chain GET /policies/file-system-replica-links coerces -- the join item returns its endpoints as objects (context, link, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbQosPolicy';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; only the family chain GET /qos-policies/buckets coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbRealm';                             Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /realms/defaults coerces -- its items carry no name (context, object_store, realm).' }
        @{ Cmdlet = 'Remove-PfbSaml2Idp';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /sso/saml2/idps/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbSnmpManager';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /snmp-managers/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbSshCaPolicy';                       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 3
            Why = 'Primary producer binds -Name correctly; only the family chain GET /ssh-certificate-authority-policies/admins coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbStorageClassTieringPolicy';         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /storage-class-tiering-policies/members coerces -- the join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbSyslogServer';                      Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /syslog-servers/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Remove-PfbTlsPolicy';                         Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /tls-policies/members coerces -- the join item returns its endpoints as objects (member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbUserGroupQuotaPolicy';              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /user-group-quota-policies/file-systems coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Remove-PfbWorkload';                          Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /workloads/tags coerces -- its items carry no name (context, copyable, key, namespace, resource, value).' }
        @{ Cmdlet = 'Remove-PfbWormPolicy';                        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /worm-data-policies/members coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Update-PfbKmip';                              Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /kmip/test coerces -- the /test endpoint returns a test-result item, not a resource, so it has no name.' }
        @{ Cmdlet = 'Update-PfbObjectStoreAccessPolicyRule';       Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 2
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-access-policies/object-store-roles coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Update-PfbObjectStoreRole';                   Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-roles/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
        @{ Cmdlet = 'Update-PfbObjectStoreTrustPolicyRule';        Parameter = 'Name';        Scope = 'Family';  Issue = '#90'; Producers = 1
            Why = 'Primary producer binds -Name correctly; only the family chain GET /object-store-roles/object-store-access-policies coerces -- the join item returns its endpoints as objects (context, member, policy) and carries no name.' }
    )
}
