# Projects bring their own tailnet rules

Some rules in the tailnet policy exist only because of one project of mine: Plouf's worker reaches proxies on friends' networks, on one port. They describe that project's design, which lives in its own (private) repository, and more projects of the same kind may follow. hanok is public. The tailnet has one policy, applied from one place, and applying it without a project's rules deletes them.

**Decision.**

- **A project keeps its rules in its repository**, `.hanok/tailnet.hujson`: `tagOwners`, `grants` and `tests` only, like a project already brings its dashboards and alert rules (`docs/conventions.md`).
- **A project owns the tags named after its repository**, `tag:<repository>-*`, and its rules stay inside them. `tailscale/combine.py` refuses a fragment that declares another tag, names a tag of mine or of another project in a `src`, `dst` or `accept`, or carries any other section. For each project tag it generates a test: it reaches none of the other tags. A project can neither open a door to my devices nor be opened by another.
- **hanok applies, and only hanok.** Its workflow fetches every fragment, combines, tests, then applies: on push to `main`, every hour (a project's merged change lands within the hour), and by hand. Any error stops it before apply; the tailnet keeps the last good policy. A missing fragment is not an error, so a second check compares the result with the policy the tailnet runs: if a tag would disappear, nothing is applied unless I run the workflow by hand with "allow tag removal".
- **One GitHub App, not one token per project.** `hanok-tailnet` has Contents: read, nothing else, and is installed only on the projects' repositories. The workflow mints a short-lived token from it on each run. Adding a project is installing the App on its repository; removing it is uninstalling (its rules go at the next run).
- **Our own script, not tailscale-acl-combiner.** The combiner appends sections and lets duplicate names through without an error; it checks nothing about who owns what. The checks are the point here, and a hundred lines of Python with no dependency do both.

**Rejected.**

- **A private repository that applies the policy**: one more repository, and the most interesting public part of hanok moves out of it.
- **Project rules in hanok, described generically**: the wording still tells a project's design, and the rules sit far from the code that needs them.
- **A token secret per project**, or a project pinging hanok on merge: secrets multiply with projects; the hourly run makes the ping unnecessary.

**Consequences.**

- A fragment's mistake blocks every apply until it is fixed; the failed run says which project and why. The Actions tab notifies me.
- A project cannot test its fragment against the tailnet before merging: it is tested in hanok within the hour. A project may run `combine.py` locally against hanok's public file for the ownership checks.
- Scheduled workflows of a public repository stop after 60 days without activity: GitHub warns by email, and any push to hanok re-enables them.
