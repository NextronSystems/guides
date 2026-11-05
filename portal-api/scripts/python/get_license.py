#!/usr/bin/env python3
"""Get a THOR license for one or more hosts from the Nextron Customer Portal.

For each host, the portal returns its existing license or issues a new one from
a suitable contract. Each license is saved as <hostname>.lic.

The credential is read from the NEXTRON_PORTAL_KEY environment variable (or
--key): a THOR download token or a personal API key. See docs/01-credentials.md.

Examples:
  get_license.py                                # license for this computer
  get_license.py web01 web02 --out-dir licenses
  get_license.py --file hosts.txt --type workstation
  get_license.py web01 --contract 1234          # only from contract #1234
  get_license.py web01 --no-issue               # only fetch an existing license

Needs Python 3.6 or newer and nothing else.
"""

import argparse
import base64
import json
import os
import platform
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PORTAL_URL = "https://portal.nextron-systems.com"
USER_AGENT = "portal-api-guide/get_license.py"

# Characters the portal accepts in a hostname.
HOSTNAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
# The portal takes any 27-character name made only of these characters for a
# hostname hash. A trailing dot makes it a hostname again: the portal ignores
# everything from the first dot on.
LOOKS_LIKE_HASH_RE = re.compile(r"^[A-Za-z0-9_-]{27}$")
CONTRACTS_RE = re.compile(r"^[0-9]+(,[0-9]+)*$")

ATTEMPTS = 3
RETRY_STATUS = (502, 503, 504)

EXIT_OK, EXIT_FAILED, EXIT_USAGE = 0, 1, 2


class PortalError(Exception):
    """An error answer from the portal. Status 0 means there was no answer."""

    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def short_name(hostname):
    """Return the name the portal licenses: the first label, in lower case."""
    return hostname.split(".", 1)[0].strip().lower()


def local_license_type():
    """Return 'workstation' or 'server' for the computer this script runs on."""
    system = platform.system()
    if system == "Darwin":
        return "workstation"
    if system == "Windows":
        # platform.win32_edition() exists from Python 3.8 on; without it, fall
        # back to 'server', which is valid on workstations too.
        edition = getattr(platform, "win32_edition", lambda: None)()
        if edition and "server" not in edition.lower():
            return "workstation"
    return "server"


def wait_before_retry(retry_after, attempt):
    try:
        seconds = int(retry_after)
    except (TypeError, ValueError):
        seconds = 5 * attempt
    time.sleep(min(max(seconds, 1), 30))


def request_license(args, hostname, issue):
    """Ask the portal for the license of one host and return it as a dict.

    GET only returns an existing license. POST returns the existing license or
    issues a new one.
    """
    name = hostname + "." if LOOKS_LIKE_HASH_RE.match(hostname) else hostname
    url = "{}/api/public/contracts/issue/{}/{}/{}".format(
        args.portal.rstrip("/"), args.contract, args.type, urllib.parse.quote(name)
    )
    if issue and args.comment:
        url += "?" + urllib.parse.urlencode({"comment": args.comment})
    request = urllib.request.Request(
        url,
        data=b"" if issue else None,
        method="POST" if issue else "GET",
        headers={
            "Authorization": args.key,
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )

    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(request, timeout=args.timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as err:
            # The portal answers errors as plain text: "ERROR: <reason>"
            message = err.read().decode("utf-8", "replace").strip()
            if message.startswith("ERROR: "):
                message = message[len("ERROR: "):]
            if err.code in RETRY_STATUS and attempt < ATTEMPTS:
                wait_before_retry(err.headers.get("Retry-After"), attempt)
                continue
            raise PortalError(err.code, message or str(err.reason))
        except (urllib.error.URLError, OSError) as err:
            if attempt < ATTEMPTS:
                wait_before_retry(None, attempt)
                continue
            reason = getattr(err, "reason", err)
            raise PortalError(0, "cannot reach {}: {}".format(args.portal, reason))


def explain(err, args, issued):
    """Turn a portal error into a message that says what to do about it."""
    message = err.message
    if err.status == 0:
        return message + " (check the network, proxy settings and --portal)"
    if err.status == 401:
        return ("the portal rejected the credential ({}). Set NEXTRON_PORTAL_KEY to a THOR "
                "download token or a personal API key, without a 'Bearer' prefix".format(message))
    if err.status == 400 and "mismatch between token" in message:
        return ("your download token belongs to one contract and --contract names another. "
                "Use --contract 0 or the token of contract {}".format(args.contract))
    if err.status == 404 and "error getting contract" in message:
        return ("contract {} was not found in your company account. "
                "Use the contract number shown in the portal (Contract #...)".format(args.contract))
    if err.status == 409 and not issued:
        return "the host has no license yet (run without --no-issue to issue one)"
    if err.status == 409:
        hint = ("no usable contract has licenses left for a {} license. Check that a matching "
                "contract is active and has licenses left".format(args.type))
        if args.type == "server":
            hint += "; a THOR Workstation contract needs --type workstation"
        return hint
    if err.status >= 500:
        return "the portal is not available right now ({}). Try again later".format(err.status)
    return "{} (HTTP {})".format(message, err.status)


def get_license(args, hostname):
    """Fetch or issue the license of one host and save it. Return a result dict."""
    result = {"hostname": hostname, "status": "failed"}
    issued = False
    try:
        try:
            lic = request_license(args, hostname, issue=False)
            result["status"] = "existing"
        except PortalError as err:
            if err.status != 409 or args.no_issue:
                raise
            issued = True
            lic = request_license(args, hostname, issue=True)
            result["status"] = "issued"
    except PortalError as err:
        result["http_status"] = err.status
        result["error"] = explain(err, args, issued)
        if err.status == 409 and not issued:
            result["status"] = "missing"
        return result

    path = os.path.join(args.out_dir, short_name(hostname) + ".lic")
    with open(path, "wb") as handle:
        handle.write(base64.b64decode(lic["blob"]))
    result.update(
        license_id=lic.get("id"),
        contract_number=lic.get("contract_number"),
        valid_from=(lic.get("starts_on_time") or "")[:10],
        valid_until=(lic.get("expires_on_time") or "")[:10],
        file=path,
    )
    return result


def read_hostnames(args):
    """Collect hostnames from the command line and --file, without duplicates."""
    names = list(args.hostnames)
    if args.file:
        with open(args.file, encoding="utf-8") as handle:
            for line in handle:
                line = line.split("#", 1)[0]
                names.extend(n for n in re.split(r"[\s,;]+", line) if n)
    if not names:
        names = [socket.gethostname()]

    unique, seen = [], set()
    for name in names:
        key = short_name(name)
        if key not in seen:
            seen.add(key)
            unique.append(name)
    return unique


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Get a THOR license for one or more hosts from the Nextron Customer Portal. "
                    "Returns the existing license of a host or issues a new one.",
        epilog="The credential comes from NEXTRON_PORTAL_KEY unless --key is given. "
               "See https://github.com/NextronSystems/portal-api-guide",
    )
    parser.add_argument("hostnames", nargs="*", metavar="HOSTNAME",
                        help="hosts to license (default: this computer). The domain part is ignored.")
    parser.add_argument("-f", "--file", help="read more hostnames from this file, one per line")
    parser.add_argument("-t", "--type", choices=("server", "workstation", "auto"), default="server",
                        help="license type to request (default: server, valid on any system). "
                             "'auto' detects the type of this computer")
    parser.add_argument("-c", "--contract", default="0",
                        help="contract number(s) to use, comma-separated (default: 0 = let the portal choose)")
    parser.add_argument("-o", "--out-dir", default=".", help="folder for the .lic files (default: current folder)")
    parser.add_argument("--comment", help="comment stored with newly issued licenses (max. 1000 characters)")
    parser.add_argument("--no-issue", action="store_true",
                        help="only fetch existing licenses, never issue a new one")
    parser.add_argument("--json", action="store_true", help="print the results as JSON")
    parser.add_argument("--key", default=os.environ.get("NEXTRON_PORTAL_KEY"),
                        help="THOR download token or API key (default: $NEXTRON_PORTAL_KEY)")
    parser.add_argument("--portal", default=os.environ.get("NEXTRON_PORTAL_URL", PORTAL_URL),
                        help="portal URL (default: %(default)s)")
    parser.add_argument("--timeout", type=float, default=60, help="seconds to wait for each answer (default: 60)")
    args = parser.parse_args(argv)

    if not args.key:
        parser.error("no credential: set NEXTRON_PORTAL_KEY or pass --key")
    if not CONTRACTS_RE.match(args.contract):
        parser.error("--contract takes contract numbers like 1234 or 1234,1240, or 0")
    if args.comment and (len(args.comment) > 1000 or "\n" in args.comment):
        parser.error("--comment must be a single line of at most 1000 characters")
    if args.type == "auto":
        args.type = local_license_type()
    return args


def print_result(result, width):
    # flush, so results and failures stay in order when both go to one log
    if result["status"] in ("existing", "issued"):
        print("{:<{w}}  {:<8}  contract #{:<6}  {} to {}  {}".format(
            result["hostname"], result["status"], result["contract_number"],
            result["valid_from"], result["valid_until"], result["file"], w=width), flush=True)
    else:
        print("{:<{w}}  {:<8}  {}".format(result["hostname"], result["status"].upper(), result["error"], w=width),
              file=sys.stderr, flush=True)


def main(argv=None):
    args = parse_args(argv)
    hostnames = read_hostnames(args)
    for name in hostnames:
        if not HOSTNAME_RE.match(name) or not short_name(name):
            print("invalid hostname: {!r} (allowed: letters, digits, '.', '-', '_')".format(name),
                  file=sys.stderr)
            return EXIT_USAGE
    os.makedirs(args.out_dir, exist_ok=True)

    width = max(len(name) for name in hostnames)
    results = []
    for name in hostnames:
        result = get_license(args, name)
        results.append(result)
        if not args.json:
            print_result(result, width)
        if result.get("http_status") == 401:
            break  # the same credential fails for every other host as well

    if args.json:
        print(json.dumps(results, indent=2))
    failed = [r for r in results if r["status"] not in ("existing", "issued")]
    if any(r.get("http_status") == 401 for r in results):
        return EXIT_USAGE
    return EXIT_FAILED if failed or len(results) < len(hostnames) else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
