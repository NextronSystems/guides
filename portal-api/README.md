# Nextron Customer Portal API Guide

Get THOR licenses for your hosts from the [Nextron Customer Portal](https://portal.nextron-systems.com) with a script instead of clicking through the portal.

This guide explains the portal API in plain terms and gives you code to copy: requests in curl, PowerShell and Python, and two ready-to-run scripts that take a hostname and save its license file.

## Quick start

1. In the portal, open **Contracts & Licenses** → **Contracts**, click the cloud button in the row of your THOR contract and copy the **THOR Download Token**.
2. Store the token in an environment variable:

   ```bash
   export NEXTRON_PORTAL_KEY='paste-the-token-here'
   ```

   ```powershell
   $env:NEXTRON_PORTAL_KEY = 'paste-the-token-here'
   ```

3. Get a license for a host:

   ```bash
   python3 scripts/python/get_license.py web01
   ```

   ```powershell
   .\scripts\powershell\Get-NextronLicense.ps1 -Hostname web01
   ```

   The script saves `web01.lic` in the current folder. If web01 already has a valid license, you get that one. Otherwise the portal issues a new one.

## Without the scripts: one request

```bash
curl -sS --fail -X POST -H "Authorization: $NEXTRON_PORTAL_KEY" -o web01.lic \
  "https://portal.nextron-systems.com/api/public/contracts/issue/0/server/web01?download=1"
```

The URL says which license you want:

```
https://portal.nextron-systems.com/api/public/contracts/issue/0/server/web01?download=1
                                                              │ │      │    │
                                                              │ │      │    └── answer with the license file (without it: JSON)
                                                              │ │      └─────── hostname: the host that gets the license
                                                              │ └────────────── license type: server or workstation
                                                              └──────────────── contract: 0 = let the portal choose
```

- **Hostname** (`web01`): the host the license is for. Use the name that the `hostname` command prints on that host. Domain and case do not matter: `WEB01.corp.example.com` gets the same license as `web01`.
- **License type** (`server`): `server` gets a license that is valid on any system. `workstation` is only for Windows workstations and Macs, and uses THOR Workstation contracts first. Not sure? Use `server`.
- **Contract** (`0`): let the portal choose. With a download token, that is always the token's own contract. A contract number such as `1234` uses only that contract.
- **`?download=1`**: the answer is the license file itself, which `-o web01.lic` saves.

**An existing license is returned, not replaced.** If web01 already has a valid license (started, not expired, not suspended), the portal returns that license and issues nothing new. Only if there is none does it issue a new license. So you can repeat the request as often as you like, as long as you ask the same way each time: the portal only looks for existing licenses on the contracts that fit the type and contract in the URL. A host with a Workstation license gets a second license if you later ask for `server`.

**To only check**, without ever issuing a license, leave out `-X POST`. You get the existing license, or an error if the host has none.

**When it fails**, curl prints the status, for example `The requested URL returned error: 409`, and saves no file. `409` means that no contract can issue the license: the contracts are used up or expired, or you asked for `server` and only have THOR Workstation contracts. [Generate a license](docs/02-generate-a-license.md#errors) lists every error and has a version of this request that prints the portal's explanation.

## Pick your task

| I want to … | Read | Credential |
|---|---|---|
| Get a license for one host or a list of hosts | [Generate a license](docs/02-generate-a-license.md) | Download token or API key |
| Issue licenses for many hosts from one specific contract, with a dry run first | [Issue many licenses](docs/03-issue-many-licenses.md) | API key |
| Find the license of a host, download licenses, see how many are left | [Find, download and count](docs/04-find-download-count.md) | API key |

New here? Start with [Credentials](docs/01-credentials.md). Terms, rules and all error messages are in the [Reference](docs/05-reference.md).

## Five things to know

1. **A THOR license belongs to one host.** The portal uses the short hostname, ignores case and drops the domain: `WEB01.corp.example.com` and `web01` are the same host.
2. **Licenses come from contracts.** A contract is what you bought, for example 500 THOR Server & Workstation licenses for one year. The portal shows each contract with its number, for example *Contract #1234*.
3. **The portal can pick the contract for you.** With your API key, pass `0` instead of a contract number and the portal takes a suitable active contract that has licenses left. A download token always uses its own contract.
4. **Server or workstation only matters if you have THOR Workstation contracts.** A server license is valid on any system. Ask for a workstation license to use up THOR Workstation contracts first.
5. **Asking twice is safe.** The license request in this guide returns the existing license of a host instead of issuing a second one, as long as you ask with the same type and contracts.

## What's in this guide

```
docs/
  01-credentials.md                  download tokens, API keys, your first request
  02-generate-a-license.md           the walkthrough: one request per host
  03-issue-many-licenses.md          bulk issue from one contract, with a dry run
  04-find-download-count.md          search, download and count licenses
  05-reference.md                    terms, contract selection, errors, troubleshooting
scripts/
  python/get_license.py              full script: Python 3.6+, no extra packages
  powershell/Get-NextronLicense.ps1  full script: Windows PowerShell 5.1 and PowerShell 7
```

## Related

- THOR can get its own license at startup when you pass a download token with `--portal-key`. Use this guide when you need the license file before THOR runs, or for hosts that cannot reach the portal.
- [THOR Seed](https://github.com/NextronSystems/nextron-helper-scripts/tree/master/thor-seed/) downloads THOR, gets a license and starts a scan in one PowerShell script.

## Feedback

Something unclear, wrong or missing? Please [open an issue](https://github.com/NextronSystems/guides/issues/new) in the guides repository and mention the Customer Portal API guide.
