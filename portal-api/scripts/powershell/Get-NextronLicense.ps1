<#
.SYNOPSIS
    Gets a THOR license for one or more hosts from the Nextron Customer Portal.

.DESCRIPTION
    For each host, the portal returns its existing license or issues a new one
    from a suitable contract. Each license is saved as <hostname>.lic.

    The credential is read from the NEXTRON_PORTAL_KEY environment variable, or
    from -PortalKey: a THOR download token or a personal API key. See
    docs/01-credentials.md in https://github.com/NextronSystems/portal-api-guide

    Works with Windows PowerShell 5.1 and PowerShell 7 on Windows, Linux and macOS.

.PARAMETER Hostname
    One or more hosts to license. Defaults to the computer the script runs on.
    The domain part of a name is ignored. Accepts pipeline input.

.PARAMETER Type
    License type to request. Server (default) is valid on any system.
    Workstation prefers THOR Workstation contracts. Auto detects the type of
    the computer the script runs on.

.PARAMETER Contract
    Contract number(s) to use, comma-separated, for example 1234 or 1234,1240.
    Default: 0, which lets the portal choose a suitable contract.

.PARAMETER OutputDirectory
    Folder for the .lic files. Default: the current folder.

.PARAMETER Comment
    Comment stored with newly issued licenses (single line, max. 1000 characters).

.PARAMETER NoIssue
    Only fetch existing licenses, never issue a new one.

.PARAMETER PortalKey
    THOR download token or personal API key. Default: $env:NEXTRON_PORTAL_KEY

.PARAMETER PortalUrl
    Portal URL. Default: $env:NEXTRON_PORTAL_URL or https://portal.nextron-systems.com

.PARAMETER Proxy
    Proxy server URL, for example http://proxy.example.com:8080

.PARAMETER TimeoutSec
    Seconds to wait for each answer. Default: 60

.EXAMPLE
    .\Get-NextronLicense.ps1
    Gets a license for this computer and saves it in the current folder.

.EXAMPLE
    .\Get-NextronLicense.ps1 -Hostname web01, web02 -OutputDirectory .\licenses

.EXAMPLE
    Get-Content .\hosts.txt | .\Get-NextronLicense.ps1 -Type Workstation

.EXAMPLE
    .\Get-NextronLicense.ps1 -Hostname web01 -Contract 1234
    Uses only contract #1234.

.EXAMPLE
    .\Get-NextronLicense.ps1 -Hostname web01 -NoIssue
    Only fetches the license web01 already has.

.OUTPUTS
    One object per host with Hostname, Status (Existing, Issued, Missing or
    Failed), ContractNumber, ValidFrom, ValidUntil, File and Error.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ComputerName', 'Name')]
    [string[]] $Hostname,

    [ValidateSet('Server', 'Workstation', 'Auto')]
    [string] $Type = 'Server',

    [ValidatePattern('^[0-9]+(,[0-9]+)*$')]
    [string] $Contract = '0',

    [string] $OutputDirectory = '.',

    [ValidateLength(0, 1000)]
    [ValidatePattern('^[^\r\n]*$')]
    [string] $Comment,

    [switch] $NoIssue,

    [string] $PortalKey = $env:NEXTRON_PORTAL_KEY,

    [string] $PortalUrl = $(if ($env:NEXTRON_PORTAL_URL) { $env:NEXTRON_PORTAL_URL } else { 'https://portal.nextron-systems.com' }),

    [string] $Proxy,

    [int] $TimeoutSec = 60
)

begin {
    $ErrorActionPreference = 'Stop'

    # Exit codes, the same as get_license.py
    $exitFailed = 1  # at least one host got no license
    $exitUsage = 2   # bad parameters or credential

    if (-not $PortalKey) {
        Write-Error 'No credential: set $env:NEXTRON_PORTAL_KEY or pass -PortalKey.' -ErrorAction Continue
        exit $exitUsage
    }

    # Windows PowerShell 5.1 does not offer TLS 1.2 by default
    if ($PSVersionTable.PSEdition -ne 'Core') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }

    function Get-LocalLicenseType {
        if ($IsMacOS) { return 'workstation' }
        if ($IsLinux) { return 'server' }
        # Windows: ProductType 1 is a workstation, 2 and 3 are servers
        try {
            if ((Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq 1) { return 'workstation' }
        } catch {
            Write-Verbose "Could not read the Windows product type, using 'server': $_"
        }
        return 'server'
    }

    # The name the portal licenses: the first label, in lower case
    function Get-ShortName([string] $Name) {
        return $Name.Split('.')[0].Trim().ToLowerInvariant()
    }

    function Format-Day($Value) {
        # PowerShell 7 turns date strings into DateTime objects, 5.1 does not
        if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('yyyy-MM-dd') }
        if ($Value) { return ([string]$Value).Substring(0, 10) }
        return ''
    }

    # Asks the portal for the license of one host. GET only returns an existing
    # license, POST returns the existing license or issues a new one.
    function Invoke-LicenseRequest([string] $Name, [string] $Method) {
        # The portal takes any 27-character name made only of these characters
        # for a hostname hash. A trailing dot makes it a hostname again.
        $target = if ($Name -match '^[A-Za-z0-9_-]{27}$') { "$Name." } else { $Name }
        $uri = '{0}/api/public/contracts/issue/{1}/{2}/{3}' -f $PortalUrl.TrimEnd('/'), $Contract, $licenseType, [uri]::EscapeDataString($target)
        if ($Method -eq 'Post' -and $Comment) {
            $uri += '?comment=' + [uri]::EscapeDataString($Comment)
        }
        $request = @{
            Method     = $Method
            Uri        = $uri
            Headers    = @{ Authorization = $PortalKey }
            UserAgent  = 'portal-api-guide/Get-NextronLicense.ps1'
            TimeoutSec = $TimeoutSec
        }
        if ($Proxy) { $request.Proxy = $Proxy }

        for ($attempt = 1; ; $attempt++) {
            Write-Verbose "$Method $uri"
            try {
                $license = Invoke-RestMethod @request
                return [pscustomobject]@{ Status = 200; License = $license; Message = $null }
            } catch {
                $response = $_.Exception.Response
                $status = if ($response) { [int]$response.StatusCode } else { 0 }
                # The portal answers errors as plain text: "ERROR: <reason>"
                $message = $_.ErrorDetails.Message
                if (-not $message -and $response -and $response.PSObject.Methods['GetResponseStream']) {
                    $message = (New-Object IO.StreamReader($response.GetResponseStream())).ReadToEnd()
                }
                if (-not $message) { $message = $_.Exception.Message }
                $message = $message.Trim() -replace '^ERROR: ', ''

                if (($status -in 0, 502, 503, 504) -and ($attempt -lt 3)) {
                    Start-Sleep -Seconds (5 * $attempt)
                    continue
                }
                if ($status -eq 0) { $message = "cannot reach ${PortalUrl}: $message" }
                return [pscustomobject]@{ Status = $status; License = $null; Message = $message }
            }
        }
    }

    # Turns a portal error into a message that says what to do about it
    function Get-Explanation($Answer, [bool] $Issued) {
        $message = $Answer.Message
        switch ($Answer.Status) {
            0 { return "$message (check the network, proxy settings and -PortalUrl)" }
            401 { return "the portal rejected the credential ($message). Set NEXTRON_PORTAL_KEY to a THOR download token or a personal API key, without a 'Bearer' prefix" }
            400 {
                if ($message -like '*mismatch between token*') {
                    return "your download token belongs to one contract and -Contract names another. Use -Contract 0 or the token of contract $Contract"
                }
            }
            404 {
                if ($message -like '*error getting contract*') {
                    return "contract $Contract was not found in your company account. Use the contract number shown in the portal (Contract #...)"
                }
            }
            409 {
                if (-not $Issued) { return 'the host has no license yet (run without -NoIssue to issue one)' }
                $hint = "no usable contract has licenses left for a $licenseType license. Check that a matching contract is active and has licenses left"
                if ($licenseType -eq 'server') { $hint += '; a THOR Workstation contract needs -Type Workstation' }
                return $hint
            }
        }
        if ($Answer.Status -ge 500) { return "the portal is not available right now ($($Answer.Status)). Try again later" }
        return "$message (HTTP $($Answer.Status))"
    }

    $licenseType = if ($Type -eq 'Auto') { Get-LocalLicenseType } else { $Type.ToLowerInvariant() }
    $names = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    # Show results as a short table; Format-List * shows every property
    $defaultView = New-Object Management.Automation.PSPropertySet('DefaultDisplayPropertySet',
        [string[]]('Hostname', 'Status', 'ContractNumber', 'ValidUntil'))
    $standardMembers = [Management.Automation.PSMemberInfo[]]@($defaultView)
}

process {
    foreach ($entry in $Hostname) {
        # Allow lists from files: skip blank lines and # comments
        $entry = ($entry -replace '#.*$', '').Trim()
        foreach ($name in ($entry -split '[\s,;]+')) {
            if ($name -and -not $seen.ContainsKey((Get-ShortName $name))) {
                $seen[(Get-ShortName $name)] = $true
                $names.Add($name)
            }
        }
    }
}

end {
    if ($names.Count -eq 0) { $names.Add([System.Net.Dns]::GetHostName()) }
    foreach ($name in $names) {
        if ($name -notmatch '^[A-Za-z0-9._-]+$' -or -not (Get-ShortName $name)) {
            Write-Error "Invalid hostname: '$name' (allowed: letters, digits, '.', '-', '_')" -ErrorAction Continue
            exit $exitUsage
        }
    }

    $directory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
    $null = New-Item -ItemType Directory -Path $directory -Force

    $failed = 0
    foreach ($name in $names) {
        $result = [pscustomobject]@{
            Hostname       = $name
            Status         = 'Failed'
            ContractNumber = $null
            ValidFrom      = $null
            ValidUntil     = $null
            File           = $null
            Error          = $null
        }
        $result | Add-Member -MemberType MemberSet -Name PSStandardMembers -Value $standardMembers

        $issued = $false
        $answer = Invoke-LicenseRequest $name 'Get'
        if ($answer.Status -eq 200) {
            $result.Status = 'Existing'
        } elseif ($answer.Status -eq 409 -and -not $NoIssue) {
            $issued = $true
            $answer = Invoke-LicenseRequest $name 'Post'
            if ($answer.Status -eq 200) { $result.Status = 'Issued' }
        }

        if ($answer.Status -eq 200) {
            $license = $answer.License
            $result.File = Join-Path $directory ((Get-ShortName $name) + '.lic')
            [IO.File]::WriteAllBytes($result.File, [Convert]::FromBase64String($license.blob))
            $result.ContractNumber = $license.contract_number
            $result.ValidFrom = Format-Day $license.starts_on_time
            $result.ValidUntil = Format-Day $license.expires_on_time
        } else {
            $failed++
            if ($answer.Status -eq 409 -and -not $issued) { $result.Status = 'Missing' }
            $result.Error = Get-Explanation $answer $issued
            Write-Error -Message "${name}: $($result.Error)" -ErrorAction Continue
        }
        $result

        if ($answer.Status -eq 401) {
            # The same credential fails for every other host as well
            exit $exitUsage
        }
    }

    if ($failed -gt 0) { exit $exitFailed }
    exit 0
}
