function Update-PfbDns {
    <#
    .SYNOPSIS
        Updates FlashBlade DNS configuration.
    .DESCRIPTION
        The Update-PfbDns cmdlet modifies attributes of a DNS configuration on the connected
        Everpure FlashBlade. Supports pipeline input and ShouldProcess for confirmation
        prompts.

        The individual typed parameters and the raw -Attributes hashtable are mutually
        exclusive: they live in separate parameter sets, so PowerShell rejects a mixed
        invocation at bind time rather than letting -Attributes silently override an
        explicitly supplied value. The -Name and -Id selectors are declared separately from
        those sets, since they are query parameters orthogonal to the request body and stay
        usable alongside either.
    .PARAMETER Name
        Selects the DNS configuration by name. Sent as the `names` query parameter.
    .PARAMETER Id
        Selects the DNS configuration by ID. Sent as the `ids` query parameter.
    .PARAMETER Domain
        The DNS domain name.
    .PARAMETER Nameservers
        An array of DNS nameserver IP addresses.
    .PARAMETER CaCertificate
        A reference to the certificate to use for validating nameservers with https
        connections.
    .PARAMETER CaCertificateGroup
        A reference to the certificate group to use for validating nameservers with https
        connections.
    .PARAMETER NewName
        A new user-specified name for the DNS configuration.
    .PARAMETER Services
        The list of services utilizing the DNS configuration.
    .PARAMETER Sources
        The network interfaces used for communication with the DNS server.
    .PARAMETER Attributes
        A hashtable of DNS attributes to update. Mutually exclusive with the individual
        typed parameters above.
    .PARAMETER Array
        The FlashBlade connection object.
    .EXAMPLE
        Update-PfbDns -Domain "example.com" -Nameservers "10.0.0.1", "10.0.0.2"

        Updates the domain and nameservers using typed parameters.
    .EXAMPLE
        Update-PfbDns -Name "mgmt-dns" -Sources "vir0"

        Restricts the mgmt-dns configuration to use the vir0 network interface.
    .EXAMPLE
        Update-PfbDns -Attributes @{ domain = "example.com" }

        Updates the domain using the raw -Attributes hashtable.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Individual')]
    param(
        # Explicit Position restores the pre-#31 positional-calling convention: adding a
        # ParameterSetName to any parameter disables PowerShell's default implicit positional
        # binding for the WHOLE function (whole-branch review finding I-1), which would
        # otherwise have silently broken `Update-PfbDns $domain $nameservers`.
        [Parameter(ParameterSetName = 'Individual', Position = 0)] [string]$Domain,
        [Parameter(ParameterSetName = 'Individual', Position = 1)] [string[]]$Nameservers,

        [Parameter()] [string]$Name,
        [Parameter()] [string]$Id,

        [Parameter(ParameterSetName = 'Individual')] [string]$CaCertificate,
        [Parameter(ParameterSetName = 'Individual')] [string]$CaCertificateGroup,
        [Parameter(ParameterSetName = 'Individual')] [string]$NewName,
        [Parameter(ParameterSetName = 'Individual')] [string[]]$Services,
        [Parameter(ParameterSetName = 'Individual')] [string[]]$Sources,

        [Parameter(ParameterSetName = 'Attributes', Mandatory, Position = 0)] [hashtable]$Attributes,
        [Parameter()] [PSCustomObject]$Array
    )

    Assert-PfbConnection -Array ([ref]$Array)

    if ($PSCmdlet.ParameterSetName -eq 'Attributes') {
        $body = $Attributes
    }
    else {
        # EVERY value-carrying parameter is guarded by $PSBoundParameters.ContainsKey, never by
        # truthiness -- see Update-PfbAdmin.ps1 for the full rationale. -Domain, -NewName, and
        # -CaCertificate/-CaCertificateGroup are all optional [string]s, so an empty string is
        # a legitimate explicit value that truthiness would silently drop.
        $body = @{}
        if ($PSBoundParameters.ContainsKey('Domain'))             { $body['domain'] = $Domain }
        if ($PSBoundParameters.ContainsKey('Nameservers'))        { $body['nameservers'] = @($Nameservers) }

        # Constraint 8(a): ca_certificate/ca_certificate_group are SCALAR references (item
        # schema is {id, name, resource_type}), so the parameter is [string] and the
        # projection is assigned INLINE as a name-reference hashtable -- constraint 7 forbids
        # an intermediate local.
        if ($PSBoundParameters.ContainsKey('CaCertificate'))      { $body['ca_certificate'] = @{ name = $CaCertificate } }
        if ($PSBoundParameters.ContainsKey('CaCertificateGroup')) { $body['ca_certificate_group'] = @{ name = $CaCertificateGroup } }

        # Exception: the body field is literally `name` (renames the resource), so the
        # parameter is -NewName, never -DnsName -- see Update-PfbWorkload / Update-PfbDataEvictionPolicy.
        if ($PSBoundParameters.ContainsKey('NewName'))            { $body['name'] = $NewName }

        if ($PSBoundParameters.ContainsKey('Services'))           { $body['services'] = @($Services) }

        # Constraint 8(b): sources is an ARRAY OF REFERENCES (item schema is
        # {id, name, resource_type}), so the parameter is [string[]] and the projection is
        # assigned INLINE.
        if ($PSBoundParameters.ContainsKey('Sources'))            { $body['sources'] = @($Sources | ForEach-Object { @{ name = $_ } }) }
    }

    # -Name/-Id are declared bare (not in the Individual/Attributes sets, constraint 17): they
    # are query parameters, orthogonal to the request body, and must stay usable alongside
    # -Attributes.
    $queryParams = @{}
    if ($PSBoundParameters.ContainsKey('Name')) { $queryParams['names'] = $Name }
    if ($PSBoundParameters.ContainsKey('Id'))   { $queryParams['ids']   = $Id }

    $target = if ($PSBoundParameters.ContainsKey('Name')) { $Name } elseif ($PSBoundParameters.ContainsKey('Id')) { $Id } else { 'DNS' }
    if ($PSCmdlet.ShouldProcess($target, 'Update DNS configuration')) {
        Invoke-PfbApiRequest -Array $Array -Method PATCH -Endpoint 'dns' -Body $body -QueryParams $queryParams
    }
}
