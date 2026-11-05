# 1. Credentials and your first request

All requests go to `https://portal.nextron-systems.com` and carry a credential in a header. The portal accepts two kinds of credentials.

## Download token or API key?

| | THOR download token | Personal API key |
|---|---|---|
| What it is | A token for one contract of your company | A key of your portal user |
| What it can do | Get licenses and downloads from its contract | Everything your user can do in the portal |
| Works with | The license request in [Generate a license](02-generate-a-license.md) | Every request in this guide |
| Who has one | Every customer with an active contract | Users of companies with API access enabled |
| Lifetime | Does not expire. If it leaks, contact Nextron. | Until you delete it in the portal and generate a new one |

Use a download token for scripts that only get licenses, for example on a deployment server. It works only for its own contract and cannot see your other contracts, licenses or users.

Use your API key for the full API: listing contracts, searching licenses, issuing many licenses with a dry run.

## Get a THOR download token

1. Log in to the portal and open **Contracts & Licenses** → **Contracts**.
2. In the row of the contract you want licenses from, click the cloud button (*Show Download Links for THOR and the THOR Seed Script*).
3. Copy the **THOR Download Token**.

The button appears only for active contracts. The token looks different each time you open the dialog. That is expected, and every version of it stays valid.

This token gets licenses from its own contract only. To let the portal choose among all your contracts, use your API key.

## Get a personal API key

1. Log in to the portal and open **Settings** → **API Key**.
2. Click **Generate New API Key** and copy the key. The portal shows it only once.

No **API Key** tab? Then API access is not enabled for your company: ask your Nextron contact to enable it. The tab is also hidden while the portal waits for you to change your password or to set up two-factor authentication.

Each user has at most one key. To replace it, delete it and generate a new one. The **API Key** tab also shows when and from which IP address the key was last used.

The key has the same rights as your user. For unattended scripts, consider a separate portal user just for automation.

## Send the credential

Put the credential in the `Authorization` header, exactly as you copied it. Do not add `Bearer` or any other prefix.

```
Authorization: <download token or API key>
```

The portal also accepts the header `X-Token` for the license request and `X-API-KEY` for `/api/v1` requests.

Keep credentials out of scripts and command lines, where they end up in files and shell histories. The examples in this guide read the credential from the environment variable `NEXTRON_PORTAL_KEY`:

```bash
export NEXTRON_PORTAL_KEY='paste-it-here'
```

```powershell
$env:NEXTRON_PORTAL_KEY = 'paste-it-here'
```

The curl examples use [jq](https://jqlang.org/) to read JSON answers.

## Test your credential

**API key:** ask the portal who you are.

```bash
curl -sS -H "Authorization: $NEXTRON_PORTAL_KEY" https://portal.nextron-systems.com/api/v1/user | jq '{username, customer_name}'
```

```powershell
Invoke-RestMethod -Uri https://portal.nextron-systems.com/api/v1/user -Headers @{ Authorization = $env:NEXTRON_PORTAL_KEY } |
    Select-Object username, customer_name
```

```python
import os
import requests

answer = requests.get(
    "https://portal.nextron-systems.com/api/v1/user",
    headers={"Authorization": os.environ["NEXTRON_PORTAL_KEY"]},
    timeout=60,
)
print(answer.status_code, answer.json()["customer_name"] if answer.ok else answer.text)
```

**Download token:** ask for the license of a host that has none, with `GET`, which never issues a license:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: $NEXTRON_PORTAL_KEY" \
  https://portal.nextron-systems.com/api/public/contracts/issue/0/server/credential-test
```

`409` means the token works: the portal knows it and found no license for `credential-test`. `401` means the portal does not accept the token.

## When your API key stops working

| Answer | Cause and fix |
|---|---|
| `401 could not auth user by api key` | The key is wrong or was deleted, your user or your company account is disabled, or API access is disabled for your company. |
| `403 password change required` | Log in to the portal and change your password. |
| `403 two factor authentication required` | Your user must use two-factor authentication. Log in to the portal and set it up. |
| `403 forbidden request (read only)` | Your user is read-only, so the portal refuses `POST` requests to `/api/v1`. |

Next: [Generate a license](02-generate-a-license.md)
