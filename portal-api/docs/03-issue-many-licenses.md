# 3. Issue licenses for many hosts from one contract

The [license request](02-generate-a-license.md) handles one host at a time and can pick the contract itself. When you want more control, use the issue endpoint of the full API. It lets you:

- choose the exact contract,
- check a request first without issuing anything (dry run),
- skip hosts that already have a license,
- set a start date,
- send hundreds of hostnames in one request.

You need a [personal API key](01-credentials.md#get-a-personal-api-key).

## Step 1: Find the contract ID

This endpoint takes the contract ID, a UUID, not the contract number. List your active contracts with both:

```bash
curl -sS -G -H "Authorization: $NEXTRON_PORTAL_KEY" \
  --data-urlencode 'query=[{"field":"status","value":"active"}]' \
  --data-urlencode 'limit=-1' \
  https://portal.nextron-systems.com/api/v1/contract/search |
  jq -r '.data[] | [.contract_number, .id, .contract_type_string, .license_count - .issued_count, .expires_on_time[:10]] | @tsv'
```

```powershell
$query = @{ query = '[{"field":"status","value":"active"}]'; limit = -1 }
(Invoke-RestMethod -Uri https://portal.nextron-systems.com/api/v1/contract/search -Body $query -Headers @{ Authorization = $env:NEXTRON_PORTAL_KEY }).data |
    Select-Object contract_number, id, contract_type_string, @{ n = 'left'; e = { $_.license_count - $_.issued_count } }, expires_on_time
```

```python
import json
import os

import requests

answer = requests.get(
    "https://portal.nextron-systems.com/api/v1/contract/search",
    headers={"Authorization": os.environ["NEXTRON_PORTAL_KEY"]},
    params={"query": json.dumps([{"field": "status", "value": "active"}]), "limit": -1},
    timeout=60,
)
answer.raise_for_status()
for c in answer.json()["data"] or []:
    left = c["license_count"] - c["issued_count"]
    print(f"#{c['contract_number']}  {c['id']}  {c['contract_type_string']}  {left} left  until {c['expires_on_time'][:10]}")
```

## Step 2: Dry run

```
POST https://portal.nextron-systems.com/api/v1/contract/issue/{contractID}
```

Send the fields as form data (`application/x-www-form-urlencoded`):

| Field | Example | Meaning |
|---|---|---|
| `hostname` | `web01 web02 db01` | The hostnames, separated by spaces, commas, semicolons or line breaks. |
| `hostname_type` | `host` | Treat every value as a hostname. Recommended: the default, `auto`, takes 27-character names for hostname hashes. |
| `check_only` | `true` | Dry run: report what would happen, issue nothing. |
| `skip_existing` | `true` | Do not issue licenses for hosts that already have a valid one. Recommended. |
| `description` | `Berlin rollout` | Comment stored with every issued license. |
| `starts_on` | `2026-11-01` | Start of the licenses, as `YYYY-MM-DD` (UTC) or a timestamp. Default: now. |

```bash
contract=8d3f2a6e-7b41-4c0a-a2e5-1f9c4b7d6e20   # the ID from step 1
curl -sS -H "Authorization: $NEXTRON_PORTAL_KEY" \
  --data-urlencode 'hostname=web01 web02 db01' \
  -d hostname_type=host -d skip_existing=true -d check_only=true \
  "https://portal.nextron-systems.com/api/v1/contract/issue/$contract" | jq
```

The answer, for a contract with one license left where web01 already has a license:

```json
{
  "success": false,
  "result": "check only",
  "total": 3,
  "ok": 2,
  "duplicate": 1,
  "issued": 0,
  "hostnames_ok": "web01 web02",
  "hostnames_unique": "web02",
  "existing": [
    {
      "hostname": "web01",
      "license_id": "5b0e8f8a-3c1d-4a51-9f53-2e7c6f0b9d14",
      "contract_id": "8d3f2a6e-7b41-4c0a-a2e5-1f9c4b7d6e20",
      "expires_on_time": "2027-10-26T00:00:00Z"
    }
  ],
  "errors": [
    { "hostname": "db01", "error": "not enough licenses" }
  ],
  "licenses": null
}
```

| Field | Meaning |
|---|---|
| `success` | `true` when `errors` is empty. |
| `errors` | Hosts with a problem, and the reason: `invalid hostname`, `invalid hostname hash`, `not enough licenses`, `hostname limit reached`, or `duplicate hostname` for a name you listed twice (the host itself still gets one license). |
| `existing` | Hosts that already have a license, current or not started yet, on any of your contracts. Only filled when you send `check_only` or `skip_existing`. |
| `hostnames_unique` | With `skip_existing`: the hosts that get a new license. |
| `hostnames_ok` | Hosts without errors, including those in `existing`. |

Empty lists come back as `null`, not `[]`. The entries in `existing` carry more fields than shown here, among them an `error` field you can ignore.

## Step 3: Issue

Send the same request without `check_only`:

```bash
curl -sS -H "Authorization: $NEXTRON_PORTAL_KEY" \
  --data-urlencode 'hostname=web01 web02 db01' \
  --data-urlencode 'description=Berlin rollout' \
  -d hostname_type=host -d skip_existing=true \
  "https://portal.nextron-systems.com/api/v1/contract/issue/$contract" | jq
```

Most problems only affect the host they concern: that host lands in `errors` and the others are still issued. One exception: if any host would go over the contract's limit of different hosts (`hostname limit reached`), the request issues nothing at all and answers `409 not enough licenses`. Run the dry run first, and check `errors` even when the status is `200`.

| Status | Meaning |
|---|---|
| 200 | The request was processed. `issued` is the number of new licenses, which is 0 when every host was skipped. `licenses` holds their IDs in the order of `hostnames_unique`. |
| 409 | Nothing was issued. A JSON answer lists the reasons in `errors`. A plain-text answer gives the reason, for example `not enough licenses`. |

Without `skip_existing`, a host that already has a license gets a second one, which uses up a license of the contract.

## Step 4: Download the licenses

Each ID in `licenses` downloads as a file:

```
GET https://portal.nextron-systems.com/api/v1/license/download/{licenseID}
```

To get all licenses of the contract at once, see [Download all licenses of a contract](04-find-download-count.md#download-all-licenses-of-a-contract).

## All steps in one script

### Python

```python
import os

import requests

PORTAL = "https://portal.nextron-systems.com"
CONTRACT_ID = "8d3f2a6e-7b41-4c0a-a2e5-1f9c4b7d6e20"  # from step 1
HOSTNAMES = ["web01", "web02", "db01"]

session = requests.Session()
session.headers["Authorization"] = os.environ["NEXTRON_PORTAL_KEY"]
url = f"{PORTAL}/api/v1/contract/issue/{CONTRACT_ID}"
form = {
    "hostname": " ".join(HOSTNAMES),
    "hostname_type": "host",
    "skip_existing": "true",
    "description": "Berlin rollout",
}

check = session.post(url, data={**form, "check_only": "true"}, timeout=300)
check.raise_for_status()
check = check.json()
for error in check["errors"] or []:
    print(f"{error['hostname']}: {error['error']}")
if not check["success"]:
    raise SystemExit("Nothing issued. Fix the errors above first.")

result = session.post(url, data=form, timeout=300)
result.raise_for_status()
result = result.json()
print(result["result"])

for hostname, license_id in zip(result["hostnames_unique"].split(), result["licenses"] or []):
    lic = session.get(f"{PORTAL}/api/v1/license/download/{license_id}", timeout=60)
    lic.raise_for_status()
    with open(f"{hostname}.lic", "wb") as f:
        f.write(lic.content)
    print(f"saved {hostname}.lic")
```

### PowerShell

```powershell
# Windows PowerShell 5.1 only: [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$portal = 'https://portal.nextron-systems.com'
$contractId = '8d3f2a6e-7b41-4c0a-a2e5-1f9c4b7d6e20'  # from step 1
$headers = @{ Authorization = $env:NEXTRON_PORTAL_KEY }
$uri = "$portal/api/v1/contract/issue/$contractId"
$form = @{
    hostname      = 'web01 web02 db01'
    hostname_type = 'host'
    skip_existing = 'true'
    description   = 'Berlin rollout'
}

$check = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body ($form + @{ check_only = 'true' })
foreach ($e in $check.errors) { "$($e.hostname): $($e.error)" }
if (-not $check.success) { throw 'Nothing issued. Fix the errors above first.' }

$result = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $form
$result.result

$issuedHosts = -split $result.hostnames_unique
for ($i = 0; $i -lt $result.licenses.Count; $i++) {
    $file = Join-Path $PWD "$($issuedHosts[$i]).lic"
    Invoke-WebRequest -Uri "$portal/api/v1/license/download/$($result.licenses[$i])" -Headers $headers -OutFile $file -UseBasicParsing
    "saved $file"
}
```

## More options

- **Upload a file of hostnames** instead of the `hostname` field: send multipart form data with the file in the field `file`, for example `curl -F file=@hosts.txt -F hostname_type=host ...`. Use either the field or the file, not both.
- **Hostname hashes:** answers list the hash of each host in `hostname_hashes`, in the order of `hostnames_ok`. Send them back with `hostname_type=hash` to work with hashes only.
- **`multi_count`** (1 to 10) is for contracts with very short license durations: each host gets one license that lasts `multi_count` times as long and uses up as many licenses.

## Errors

| Status | Message | What it means |
|---|---|---|
| 400 | `form validation failed` | A field has an invalid value, for example `hostname_type` or `multi_count`. |
| 400 | `invalid start date format` | `starts_on` is not a date. |
| 400 | `hostnames must be given either inline or as a file, not both` | Send `hostname` or `file`. |
| 403 | `forbidden request (read only)` | Your user is read-only. |
| 404 | `error getting contract` | No contract with this ID in your account. |
| 409 | `not enough licenses` | The contract has no licenses left for this request, or a host would go over its host limit. |
| 500 | `error creating license, ..., error: <reason>` | The contract cannot issue licenses. The reason is at the end, for example `contract is disabled`, `current time is before contract startdate` or `current time is after contract enddate`. |

Next: [Find, download and count licenses](04-find-download-count.md)
