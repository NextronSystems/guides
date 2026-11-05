# 5. Reference

## Terms

| Term | Meaning |
|---|---|
| Contract | What you bought: a number of licenses of one contract type, valid for a period. |
| Contract number | The number the portal shows as *Contract #1234*. Used by the [license request](02-generate-a-license.md). |
| Contract ID | The UUID of a contract, for example `8d3f2a6e-7b41-4c0a-a2e5-1f9c4b7d6e20`. Used by `/api/v1`. |
| Contract type | The product and license model of a contract, for example *THOR Server & Workstation*. It sets the license type. |
| License | A file (`.lic`) that allows THOR to run on one host for a period. |
| License type | What a license allows, see below. |
| Hostname hash | What the portal stores instead of the hostname. 27 characters, for example `sqQFAQE1raHO0y8OISn5jL9nqn8`. |
| THOR download token | A credential for one contract that gets licenses and downloads, see [Credentials](01-credentials.md). |
| API key | A credential with the rights of your portal user, see [Credentials](01-credentials.md). |

## License types

| License type | Valid on | Notes |
|---|---|---|
| Server & Workstation | All systems: servers and workstations, Windows, Linux and macOS | The usual THOR license. |
| Workstation | Windows workstations and macOS | Not valid on Windows Server or Linux, including Linux desktops. |
| Forensic Lab | All systems | Adds lab use: scanning mounted images, dropzone mode, several scans at once. Usually limited to one host per contract. |
| Compromise Assessment | All systems | Like Server & Workstation. When the first license is issued, the contract is shortened to the license duration, so all its licenses end together. |
| Silent | Any host | Not bound to a host: the contract issues one license that works everywhere. Scans report no alerts or warnings, for testing a rollout without spending other licenses. |
| Thunderstorm | All systems | Only for THOR Thunderstorm, the web service mode. |
| Incident Response | Not bound to a host | Allows lab scanning and dropzone mode. |

Licenses for Nextron's management products (Management Center, Analysis Cockpit, Security Center) are not bound to hosts and are not covered here.

## How the license request chooses a contract

The [license request](02-generate-a-license.md) `/api/public/contracts/issue/{contracts}/{type}/{hostname}` goes through these steps:

1. **Candidates.**
   - `0` with an API key: all contracts of your company.
   - `0` with a download token: the token's contract.
   - One or more contract numbers: these contracts. An unknown number answers `404`.
2. **Inactive contracts are dropped:** suspended, not started yet, or expired.
3. **With `0` and an API key, or with a list of numbers,** contract types that are never chosen automatically are dropped: Aurora, THOR Lite, management products and non-host-based Thunderstorm.
4. **With `0` and an API key**, THOR Forensic Lab, THOR Thunderstorm and THOR Silent contracts are dropped as well. Name them by number to use them.
5. **Type:** `server` drops THOR Workstation contracts. `workstation` keeps every contract that covers workstations.
6. **Order:** THOR Workstation first, then THOR Server & Workstation and THOR On Demand, then THOR Compromise Assessment, then Forensic Lab, Thunderstorm and Silent.
7. **Existing license:** the first currently valid license of the host on these contracts, in this order, is returned. A license that is not bound to a host, such as a Silent license, counts for every host.
8. **New license** (`POST` only): issued from the first contract in this order that still has licenses left and has not reached its host limit.

A license is currently valid if it has started, has not expired and is not suspended.

## Hostnames

- Allowed characters: letters, digits, `.`, `-` and `_`.
- The portal licenses the part before the first dot, in lower case. `Web01.Corp.Example.com` → `web01`.
- The portal stores and shows a hash of that name, never the name itself.
- A name of exactly 27 letters, digits, `-` or `_` is taken for a hash. Add a dot at the end to make it a hostname.
- Contracts can limit the number of different hosts (`hostname_limit` in the contract). THOR Forensic Lab contracts allow one host. Issuing another license for the same host is always possible while licenses are left.

## Endpoints in this guide

| Method | Path | Credential | Purpose |
|---|---|---|---|
| GET, POST | `/api/public/contracts/issue/{contracts}/{type}/{hostname}` | Token or API key | [Get or issue the license of a host](02-generate-a-license.md) |
| GET | `/api/v1/user` | API key | [Your user](01-credentials.md#test-your-credential) |
| GET | `/api/v1/contract/search` | API key | [List contracts](03-issue-many-licenses.md#step-1-find-the-contract-id) |
| GET | `/api/v1/contract/get/{contractID}` | API key | One contract |
| GET | `/api/v1/contract/count` | API key | [License counts per contract type](04-find-download-count.md#how-many-licenses-are-left) |
| GET | `/api/v1/contract-options` | API key | Names of contract and license types |
| POST | `/api/v1/contract/issue/{contractID}` | API key | [Issue licenses for many hosts](03-issue-many-licenses.md) |
| GET | `/api/v1/contract/download-licenses/{contractID}` | API key | [All licenses of a contract as ZIP](04-find-download-count.md#download-all-licenses-of-a-contract) |
| GET | `/api/v1/license/search` | API key | [Search licenses](04-find-download-count.md#find-the-license-of-a-host) |
| GET | `/api/v1/license/get/{licenseID}` | API key | One license as JSON |
| GET | `/api/v1/license/download/{licenseID}` | API key | [One license file](04-find-download-count.md#download-a-license) |
| POST | `/api/v1/license/edit/{licenseID}` | API key | Set the comment (`description`) and suspend (`disabled=true`) or resume a license. Send both fields: a missing one is reset. |

The base URL is `https://portal.nextron-systems.com`. The portal's own reference for `/api/v1` is under **Settings** → **API Documentation** once API access is enabled for your company.

## Error messages

The portal answers errors as plain text, `ERROR: <reason>`, with the HTTP status code. Successful answers are JSON or a file. Exceptions: the issue endpoint of the full API answers `409` with JSON when every host failed, and the `503` answer during maintenance has no `ERROR:` prefix.

| Message | Status | Meaning | Details |
|---|---|---|---|
| `contract not found or no permission` | 404 | Contract ID not in your account | [Reference](#endpoints-in-this-guide) |
| `could not auth user by api key` | 401 | API key wrong or deleted, user or company disabled, or API access disabled | [Credentials](01-credentials.md#when-your-api-key-stops-working) |
| `error creating license, ...` | 500 | The contract cannot issue licenses; the reason is at the end | [Issue many](03-issue-many-licenses.md#errors) |
| `error getting contract` | 404 | Contract number or ID not in your account | [Generate](02-generate-a-license.md#errors) |
| `form validation failed` | 400 | A form field of a `POST` has an invalid value | [Issue many](03-issue-many-licenses.md#errors) |
| `forbidden request (read only)` | 403 | Your user is read-only; `POST` requests to `/api/v1` are refused | [Credentials](01-credentials.md#when-your-api-key-stops-working) |
| `invalid token` | 401 | The portal does not accept the credential, or your company account is disabled | [Credentials](01-credentials.md#send-the-credential) |
| `license not found or no permission` | 404 | License ID not in your account | [Find](04-find-download-count.md#download-a-license) |
| `mismatch between token and selected contract` | 400 | The download token belongs to another contract | [Generate](02-generate-a-license.md#errors) |
| `missing authorization header or token` | 401 | No credential sent | [Credentials](01-credentials.md#send-the-credential) |
| `no contract found that holds a license for this hostname` | 409 | `GET`: the host has no license | [Generate](02-generate-a-license.md#get-or-post) |
| `no contract found that could be used to issue a license for this hostname` | 409 | `POST`: no contract can issue the license | [Generate](02-generate-a-license.md#errors) |
| `not enough licenses` | 409 | The contract has no licenses left, or a host would go over its host limit | [Issue many](03-issue-many-licenses.md#errors) |
| `password change required` | 403 | Log in to the portal and change your password | [Credentials](01-credentials.md#when-your-api-key-stops-working) |
| `two factor authentication required` | 403 | Set up two-factor authentication in the portal | [Credentials](01-credentials.md#when-your-api-key-stops-working) |
| `unauthenticated request (invalid auth cookie)` | 401 | An `/api/v1` request without credential | [Credentials](01-credentials.md#send-the-credential) |
| `validation failed, ...` | 400 | Invalid URL part (such as a hostname with other characters than letters, digits, `.`, `-` and `_`), or an unknown or repeated query parameter | [Generate](02-generate-a-license.md#errors) |

## Troubleshooting

**`401` although the credential is right.**
Check that the header holds only the credential: no `Bearer` prefix, no quotes, no trailing line break. Download tokens work only with the license request, not with `/api/v1`.

**The portal issued a second license for a host that already had one.**
The license request only returns licenses from the contracts it considers. A host licensed from a contract outside that set gets a new license: for example a host with a THOR Workstation license that you ask a `server` license for, or a host with a Forensic Lab license when you pass `0`. Ask with the same type and contracts every time. The issue endpoint of the full API issues a second license unless you send `skip_existing=true`.

**THOR does not accept the license.**
Compare the hostname: run `hostname` on the host and make sure its short name is the one you requested. Check that the license type fits, for example that a Workstation license is not used on a server.

**It works with curl but not with Windows PowerShell 5.1.**
Windows PowerShell 5.1 may not offer TLS 1.2. Run `[Net.ServicePointManager]::SecurityProtocol = 'Tls12'` first. The PowerShell script does this for you.

**Requests must go through a proxy.**
curl and the Python script use the `HTTPS_PROXY` environment variable. The PowerShell script has a `-Proxy` parameter.

**`400 validation failed, unknownQueryParam`.**
The portal does not know this query parameter. The license request uses only `download` and `comment`. Each query parameter may appear once.
