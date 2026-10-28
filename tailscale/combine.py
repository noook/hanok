#!/usr/bin/env python3
"""Build the tailnet policy: hanok's own file plus the fragments my projects bring (docs/adr/0007).

    combine.py [--fetch | --fragments DIR] --out FILE

A project (a repository of mine) brings `.hanok/tailnet.hujson` with only `tagOwners`, `grants` and `tests`, and
owns the tags named after it: repository `plouf` owns `tag:plouf-*`, and nothing else. Every rule a fragment
writes stays inside its own tags, so a project can never open a door to my devices, to hanok's services, or to
another project. On top, every project tag gets a generated test: it reaches no tag outside its project.

--fetch reads the fragments from every repository the GitHub App's installation sees (GITHUB_TOKEN must be an
installation token). Any error stops the build: applying without a fragment would delete that project's rules.
--fragments reads `<repo>.hujson` files from a directory instead (local tests).

--guard-live compares the result with the policy the tailnet runs now (TS_OAUTH_ID / TS_OAUTH_SECRET) and stops if
a tag would disappear: a project whose fragment went missing (App not installed, file moved) would otherwise lose its
rules, and its machines their access, without anyone deciding it. ALLOW_TAG_REMOVAL=true lets a deliberate removal
through (the workflow's manual run has a checkbox for it). Only counts are printed: the logs may be public.
"""
import argparse, json, os, re, sys, urllib.error, urllib.parse, urllib.request
from typing import NoReturn

PARENT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "policy.hujson")
FRAGMENT_PATH = ".hanok/tailnet.hujson"
ALLOWED = {"tagOwners", "grants", "tests"}
GRANT_KEYS = {"src", "dst", "ip"}
TEST_KEYS = {"src", "accept", "deny"}


def fail(msg) -> NoReturn:
    sys.exit(f"combine: {msg}")


def hujson_to_json(text):
    """HuJSON (JSON with comments and trailing commas) to plain JSON, strings left untouched."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1]); i = j + 1
        elif text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j < 0:
                fail("unterminated /* comment")
            i = j + 2
        else:
            out.append(c); i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def load(text, where):
    try:
        doc = json.loads(hujson_to_json(text))
    except json.JSONDecodeError as e:
        fail(f"{where}: not valid HuJSON ({e})")
    if not isinstance(doc, dict):
        fail(f"{where}: not an object")
    return doc


def tag_of(target):
    """`tag:x:443` or `tag:x` -> `tag:x`; anything else -> None."""
    if not isinstance(target, str) or not target.startswith("tag:"):
        return None
    return ":".join(target.split(":")[:2])


def check_fragment(project, doc, taken):
    where = f"{project} ({FRAGMENT_PATH})"
    prefix = f"tag:{project}-"
    extra = set(doc) - ALLOWED
    if extra:
        fail(f"{where}: only {sorted(ALLOWED)} are allowed, not {sorted(extra)}")
    owners = doc.get("tagOwners", {})
    if not isinstance(owners, dict) or not owners:
        fail(f"{where}: tagOwners must declare at least one tag")
    for tag, who in owners.items():
        if not tag.startswith(prefix) or not re.fullmatch(r"tag:[a-z0-9-]+", tag):
            fail(f"{where}: {tag} is not one of this project's tags ({prefix}…)")
        if who != []:
            fail(f"{where}: {tag} must be owned by the tailnet's admins only ([])")
        if tag in taken:
            fail(f"{where}: {tag} is already declared by {taken[tag]}")
        taken[tag] = project
    own = set(owners)

    def inside(targets, field, i, kind):
        if not isinstance(targets, list) or not targets:
            fail(f"{where}: {kind} {i}: {field} must be a non-empty list")
        for t in targets:
            if tag_of(t) not in own:
                fail(f"{where}: {kind} {i}: {field} {t!r} is outside this project's tags")

    for i, g in enumerate(doc.get("grants", [])):
        if set(g) - GRANT_KEYS or not {"src", "dst", "ip"} <= set(g):
            fail(f"{where}: grant {i}: exactly src, dst and ip")
        inside(g["src"], "src", i, "grant")
        inside(g["dst"], "dst", i, "grant")
    for i, t in enumerate(doc.get("tests", [])):
        if set(t) - TEST_KEYS or "src" not in t:
            fail(f"{where}: test {i}: src, and accept and/or deny only")
        inside([t["src"]], "src", i, "test")
        if "accept" in t:
            inside(t["accept"], "accept", i, "test")
    return own


def fetch_fragments():
    token = os.environ.get("GITHUB_TOKEN") or fail("--fetch needs GITHUB_TOKEN (the App's installation token)")
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")

    def get(url, accept="application/vnd.github+json"):
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": accept,
                                                   "X-GitHub-Api-Version": "2022-11-28"})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, ""

    repos, page = [], 1
    while True:
        status, body = get(f"{api}/installation/repositories?per_page=100&page={page}")
        if status != 200:
            fail(f"listing the App's repositories answered {status}")
        batch = json.loads(body)["repositories"]
        repos += [r["full_name"] for r in batch]
        if len(batch) < 100:
            break
        page += 1
    fragments = {}
    for full in sorted(repos):
        status, body = get(f"{api}/repos/{full}/contents/{FRAGMENT_PATH}", "application/vnd.github.raw")
        if status == 404:
            continue
        if status != 200:
            fail(f"{full}: reading {FRAGMENT_PATH} answered {status}")
        fragments[full.split("/")[1]] = body
    print(f"combine: {len(repos)} repositories, fragments from {sorted(fragments) or 'none'}")
    return fragments


def guard_live(policy):
    cid, secret = os.environ.get("TS_OAUTH_ID"), os.environ.get("TS_OAUTH_SECRET")
    if not cid or not secret:
        fail("--guard-live needs TS_OAUTH_ID and TS_OAUTH_SECRET")
    api = "https://api.tailscale.com/api/v2"
    form = urllib.parse.urlencode({"client_id": cid, "client_secret": secret}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(f"{api}/oauth/token", data=form), timeout=30) as r:
            token = json.loads(r.read())["access_token"]
        req = urllib.request.Request(f"{api}/tailnet/-/acl",
                                     headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            live = json.loads(r.read())
    except (urllib.error.URLError, KeyError, json.JSONDecodeError) as e:
        fail(f"could not read the tailnet's current policy ({type(e).__name__})")
    gone = set(live.get("tagOwners") or {}) - set(policy.get("tagOwners", {}))
    if not gone:
        print("combine: no tag of the running policy disappears")
    elif os.environ.get("ALLOW_TAG_REMOVAL") == "true":
        print(f"combine: {len(gone)} tag(s) removed on purpose (ALLOW_TAG_REMOVAL)")
    else:
        fail(f"{len(gone)} tag(s) of the running policy would disappear. If a project's fragment is missing, "
             "install the App on its repository; if the removal is wanted, run the workflow by hand with "
             "'allow tag removal'. Compare tagOwners with the admin console to see which.")


def main():
    ap = argparse.ArgumentParser()
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--fetch", action="store_true")
    src.add_argument("--fragments")
    ap.add_argument("--out", required=True)
    ap.add_argument("--guard-live", action="store_true")
    args = ap.parse_args()

    with open(PARENT) as f:
        policy = load(f.read(), "tailscale/policy.hujson")
    if args.fetch:
        texts = fetch_fragments()
    else:
        texts = {}
        for name in sorted(os.listdir(args.fragments)):
            if name.endswith(".hujson"):
                with open(os.path.join(args.fragments, name)) as f:
                    texts[name[:-len(".hujson")]] = f.read()

    taken = {t: "hanok" for t in policy.get("tagOwners", {})}
    parent_tags = sorted(taken)
    projects = {}
    for repo, text in texts.items():
        project = re.sub(r"[^a-z0-9-]", "-", repo.lower())
        projects[project] = check_fragment(project, load(text, repo), taken)
        doc = load(text, repo)
        policy.setdefault("tagOwners", {}).update(doc.get("tagOwners", {}))
        policy.setdefault("grants", []).extend(doc.get("grants", []))
        policy.setdefault("tests", []).extend(doc.get("tests", []))

    # A project's tags reach nothing outside the project: hanok's tags and every other project's.
    for project, own in sorted(projects.items()):
        outside = parent_tags + sorted(t for p, ts in projects.items() if p != project for t in ts)
        for tag in sorted(own):
            if outside:
                policy["tests"].append({"src": tag, "deny": [f"{t}:{port}" for t in outside for port in (22, 443)]})

    with open(args.out, "w") as f:
        f.write("// GENERATED by tailscale/combine.py from tailscale/policy.hujson and the projects' fragments.\n")
        json.dump(policy, f, indent="\t")
        f.write("\n")
    print(f"combine: {len(policy.get('grants', []))} grants, {len(policy.get('tests', []))} tests -> {args.out}")
    if args.guard_live:
        guard_live(policy)


if __name__ == "__main__":
    main()
