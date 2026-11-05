# 4. Find, download and count licenses

Everything on this page needs a [personal API key](01-credentials.md#get-a-personal-api-key).

## How many licenses are left?

Per contract, use the contract list from [Issue many licenses, step 1](03-issue-many-licenses.md#step-1-find-the-contract-id). Licenses left = `license_count` − `issued_count`.

Per contract type, summed over your contracts that have not expired and are not suspended:

```
GET https://portal.nextron-systems.com/api/v1/contract/count
```

```json
[
  { "contract_type": 106, "contract_count": 2, "license_count": 500, "issued_count": 312 },
  { "contract_type": 105, "contract_count": 1, "license_count": 200, "issued_count": 200 }
]
```

The contract types are numbers. Their names are in `contract_types` of `GET /api/v1/contract-options`:

```python
import os

import requests

PORTAL = "https://portal.nextron-systems.com"
session = requests.Session()
session.headers["Authorization"] = os.environ["NEXTRON_PORTAL_KEY"]

names = session.get(f"{PORTAL}/api/v1/contract-options", timeout=60).json()["contract_types"]
for row in session.get(f"{PORTAL}/api/v1/contract/count", timeout=60).json() or []:
    name = names.get(str(row["contract_type"]), {}).get("name", row["contract_type"])
    left = row["license_count"] - row["issued_count"]
    print(f"{name}: {left} of {row['license_count']} left")
```

```powershell
$portal = 'https://portal.nextron-systems.com'
$headers = @{ Authorization = $env:NEXTRON_PORTAL_KEY }
$names = (Invoke-RestMethod -Uri "$portal/api/v1/contract-options" -Headers $headers).contract_types
$counts = Invoke-RestMethod -Uri "$portal/api/v1/contract/count" -Headers $headers
foreach ($row in $counts) {
    [pscustomobject]@{
        Type  = $names."$($row.contract_type)".name
        Left  = $row.license_count - $row.issued_count
        Total = $row.license_count
    }
}
```

## Find the license of a host

```
GET https://portal.nextron-systems.com/api/v1/license/search?query=[{"field":"hostname","value":"web01"}]
```

The portal hashes the plain hostname before it searches, so `web01`, `WEB01` and `web01.corp.example.com` all find the license of web01. Search for one host per request: the hostname filter does not take several names. For a hostname of exactly 27 characters, add a dot at the end ([why](02-generate-a-license.md#hostnames)).

Add `{"field":"status","value":"active"}` to skip expired licenses:

```bash
curl -sS -G -H "Authorization: $NEXTRON_PORTAL_KEY" \
  --data-urlencode 'query=[{"field":"hostname","value":"web01"},{"field":"status","value":"active"}]' \
  https://portal.nextron-systems.com/api/v1/license/search |
  jq -r '.data[] | [.id, .contract_number, .status, .starts_on_time[:10], .expires_on_time[:10]] | @tsv'
```

```powershell
$query = @{ query = '[{"field":"hostname","value":"web01"},{"field":"status","value":"active"}]' }
(Invoke-RestMethod -Uri https://portal.nextron-systems.com/api/v1/license/search -Body $query -Headers @{ Authorization = $env:NEXTRON_PORTAL_KEY }).data |
    Select-Object id, contract_number, status, starts_on_time, expires_on_time
```

```python
import json
import os

import requests

query = [{"field": "hostname", "value": "web01"}, {"field": "status", "value": "active"}]
answer = requests.get(
    "https://portal.nextron-systems.com/api/v1/license/search",
    headers={"Authorization": os.environ["NEXTRON_PORTAL_KEY"]},
    params={"query": json.dumps(query)},
    timeout=60,
)
answer.raise_for_status()
for lic in answer.json()["data"] or []:
    print(lic["id"], lic["contract_number"], lic["status"], lic["expires_on_time"][:10])
```

The answer has the matching licenses in `data` and their number in `total`. `status` is `active`, `upcoming` or `expired`. Suspended licenses do not appear in searches.

## Download a license

```
GET https://portal.nextron-systems.com/api/v1/license/download/{licenseID}
```

The answer is the license file. Its name in the portal is in the `Content-Disposition` header.

```bash
curl -sS --fail -H "Authorization: $NEXTRON_PORTAL_KEY" -o web01.lic \
  https://portal.nextron-systems.com/api/v1/license/download/5b0e8f8a-3c1d-4a51-9f53-2e7c6f0b9d14
```

```powershell
Invoke-WebRequest -Uri https://portal.nextron-systems.com/api/v1/license/download/5b0e8f8a-3c1d-4a51-9f53-2e7c6f0b9d14 `
    -Headers @{ Authorization = $env:NEXTRON_PORTAL_KEY } -OutFile web01.lic -UseBasicParsing
```

## Download all licenses of a contract

```
GET https://portal.nextron-systems.com/api/v1/contract/download-licenses/{contractID}
```

The answer is a ZIP file with one license file per license. Licenses whose file is no longer stored are listed in `expired.txt` inside the ZIP.

```bash
curl -sS --fail -H "Authorization: $NEXTRON_PORTAL_KEY" -o licenses.zip \
  https://portal.nextron-systems.com/api/v1/contract/download-licenses/8d3f2a6e-7b41-4c0a-a2e5-1f9c4b7d6e20
```

## Download the results of a search

Add `download=1` to a license search to get the files of all matching licenses: one license file, or a ZIP file when several match. Set `limit=-1`, because a search returns only 10 results by default.

```bash
curl -sS --fail -G -H "Authorization: $NEXTRON_PORTAL_KEY" -o licenses.zip \
  --data-urlencode 'query=[{"field":"status","value":"active"}]' \
  -d limit=-1 -d download=1 \
  https://portal.nextron-systems.com/api/v1/license/search
```

## Licenses that expire soon

```bash
curl -sS -G -H "Authorization: $NEXTRON_PORTAL_KEY" \
  --data-urlencode 'query=[{"field":"status","value":"active"},{"field":"expires_on","value":"<=2026-12-31"}]' \
  -d limit=-1 \
  https://portal.nextron-systems.com/api/v1/license/search |
  jq -r '.data[] | [.expires_on_time[:10], .contract_number, .description] | @tsv'
```

## Export to CSV

Add `csv=1` to a contract search to get all matches as a CSV file, separated by semicolons. `limit` and `offset` do not apply.

```bash
curl -sS --fail -G -H "Authorization: $NEXTRON_PORTAL_KEY" -o contracts.csv \
  --data-urlencode 'query=[{"field":"status","value":"active"}]' -d csv=1 \
  https://portal.nextron-systems.com/api/v1/contract/search
```

## Search syntax

Both `/api/v1/license/search` and `/api/v1/contract/search` take these query parameters:

| Parameter | Meaning |
|---|---|
| `query` | Filters as a JSON array: `[{"field": "<name>", "value": "<expression>"}, ...]`. All filters must match. URL-encode it. |
| `limit` | Number of results. Default: 10. `-1` returns all. |
| `offset` | Number of results to skip, for paging. |
| `order_field` | Field to sort by. Default: the record ID. |
| `order_dir` | `ASC` or `DESC` (default). |

Expressions in `value`:

| Expression | Matches |
|---|---|
| `web` | Text fields: values that contain `web`, ignoring case |
| `a\|b` | `a` or `b` |
| `NOT expired` | Everything but `expired` |
| `>=2026-01-01`, `<2027-01-01` | Dates after or before; also `>`, `<=` |
| `2026-01-01 - 2026-12-31` | Dates in a range |
| `>10`, `10-20` | Numbers |

Useful license fields: `hostname`, `status`, `starts_on`, `expires_on`, `description`, `contract_number`, `contract_id`, `created`.
Useful contract fields: `contract_number`, `status`, `contract_type`, `expires_on`, `license_count`, `description`.

The portal rejects unknown fields and parameters with `400`.

Next: [Reference](05-reference.md)
