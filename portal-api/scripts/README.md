# Scripts

Two scripts that do the same thing: get a THOR license for one or more hosts and save each license as `<hostname>.lic`.

For each host, the script first asks the portal for an existing license. If there is none, it asks the portal to issue one. So you can run the script as often as you like without spending licenses twice, as long as you keep the same `--type` and `--contract`: the portal only looks for existing licenses on the contracts that fit the request ([details](../docs/02-generate-a-license.md#which-contract-does-the-portal-choose)).

| | [`python/get_license.py`](python/get_license.py) | [`powershell/Get-NextronLicense.ps1`](powershell/Get-NextronLicense.ps1) |
|---|---|---|
| Runs on | Python 3.6 or newer, nothing to install | Windows PowerShell 5.1, PowerShell 7 on Windows, Linux and macOS |
| Credential | `NEXTRON_PORTAL_KEY` or `--key` | `$env:NEXTRON_PORTAL_KEY` or `-PortalKey` |

The credential is a THOR download token or a personal API key, see [Credentials](../docs/01-credentials.md).

## Python

```bash
export NEXTRON_PORTAL_KEY='your-token'

python3 get_license.py                                  # this computer
python3 get_license.py web01 web02 db01 -o licenses     # several hosts, into ./licenses
python3 get_license.py -f hosts.txt -t workstation      # hosts from a file
python3 get_license.py web01 -c 1234                    # only from contract #1234
python3 get_license.py web01 --no-issue                 # only fetch an existing license
python3 get_license.py -f hosts.txt --json > result.json
```

```
web01  issued    contract #1234    2026-10-26 to 2027-10-26  licenses/web01.lic
web02  existing  contract #1234    2026-03-02 to 2027-03-02  licenses/web02.lic
db01   FAILED    no usable contract has licenses left for a server license. Check that a matching contract is active and has licenses left; a THOR Workstation contract needs --type workstation
```

| Option | Meaning |
|---|---|
| `HOSTNAME ...` | Hosts to license. Default: this computer. |
| `-f`, `--file FILE` | Read more hostnames from a file: one or more per line, `#` starts a comment. |
| `-t`, `--type` | `server` (default, valid on any system), `workstation`, or `auto` to detect the type of this computer. |
| `-c`, `--contract` | Contract number(s), comma-separated. Default: `0`, the portal chooses. |
| `-o`, `--out-dir DIR` | Folder for the license files. Default: the current folder. |
| `--comment TEXT` | Comment stored with newly issued licenses. |
| `--no-issue` | Only fetch existing licenses, never issue one. |
| `--json` | Print the results as JSON. |
| `--key KEY` | Credential. Default: `NEXTRON_PORTAL_KEY`. |
| `--portal URL` | Portal URL. Default: `NEXTRON_PORTAL_URL` or `https://portal.nextron-systems.com`. |
| `--timeout SECONDS` | How long to wait for each answer. Default: 60. |

## PowerShell

```powershell
$env:NEXTRON_PORTAL_KEY = 'your-token'

.\Get-NextronLicense.ps1                                            # this computer
.\Get-NextronLicense.ps1 -Hostname web01, web02 -OutputDirectory .\licenses
Get-Content .\hosts.txt | .\Get-NextronLicense.ps1 -Type Workstation
.\Get-NextronLicense.ps1 -Hostname web01 -Contract 1234
.\Get-NextronLicense.ps1 -Hostname web01 -NoIssue
.\Get-NextronLicense.ps1 -Hostname web01, web02 | Export-Csv result.csv -NoTypeInformation
```

```
Hostname Status   ContractNumber ValidUntil
-------- ------   -------------- ----------
web01    Issued             1234 2027-10-26
web02    Existing           1234 2027-03-02
```

The script returns one object per host with `Hostname`, `Status` (`Existing`, `Issued`, `Missing` or `Failed`), `ContractNumber`, `ValidFrom`, `ValidUntil`, `File` and `Error`. `Format-List *` shows all of them. Failures are also written as errors.

| Parameter | Meaning |
|---|---|
| `-Hostname` | Hosts to license. Default: this computer. Takes pipeline input. |
| `-Type` | `Server` (default, valid on any system), `Workstation`, or `Auto` to detect the type of this computer. |
| `-Contract` | Contract number(s), comma-separated. Default: `0`, the portal chooses. |
| `-OutputDirectory` | Folder for the license files. Default: the current folder. |
| `-Comment` | Comment stored with newly issued licenses. |
| `-NoIssue` | Only fetch existing licenses, never issue one. |
| `-PortalKey` | Credential. Default: `$env:NEXTRON_PORTAL_KEY`. |
| `-PortalUrl` | Portal URL. Default: `$env:NEXTRON_PORTAL_URL` or `https://portal.nextron-systems.com`. |
| `-Proxy` | Proxy URL, for example `http://proxy.example.com:8080`. |
| `-TimeoutSec` | How long to wait for each answer. Default: 60. |

`Get-Help .\Get-NextronLicense.ps1 -Full` shows the built-in help.

If Windows blocks the script because it was downloaded, unblock it once: `Unblock-File .\Get-NextronLicense.ps1`.

## Exit codes

Both scripts return the same exit codes:

| Code | Meaning |
|---|---|
| 0 | Every host has its license file. |
| 1 | At least one host got no license. The output says why. |
| 2 | Wrong parameters, or the portal rejected the credential. |

## Behavior worth knowing

- **Hostnames** are sent as given. The portal uses the short name in lower case, so the file of `WEB01.corp.example.com` is `web01.lic`. Names that differ only in domain or case count once.
- **Type `auto`** detects the computer the script runs on: macOS and Windows client editions are workstations, Windows Server and Linux are servers. Use it when the script licenses its own host.
- **Retries:** when the portal is unreachable or answers `502`, `503` or `504`, the scripts try twice more, waiting up to 30 seconds in between. Repeating a request is safe because the portal returns the license it issued the first time.
- **27-character hostnames** get a trailing dot, so the portal does not take them for hostname hashes ([why](../docs/02-generate-a-license.md#hostnames)).
- **Existing files** with the same name are overwritten.
