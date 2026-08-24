# Upgrading

## Manager-owned vs. user-owned files

A personal config repo (forked from [machine-config](https://github.com/p-victor/machine-config)'s `template/`) splits cleanly into two parts:

| | Files | Who touches it |
|---|---|---|
| **Manager-owned** | `install.sh`, `config`, `manager.lock` | `mcm upgrade` — never hand-edit these (except once, via `config init`, to set your repo URL — `upgrade` preserves that) |
| **User-owned** | `environments/`, `modules/`, `local.env.example`, `README.md`, everything else | You |

That's the whole rule. `mcm upgrade` only ever touches the three manager-owned files — it never looks at `environments/` or `modules/`, so there's nothing to merge and no risk of it clobbering something you wrote. The tradeoff, made deliberately: a fix to an *example* module or environment in the template never propagates to a repo that already forked it. Only the bootstrap/version-pin machinery updates automatically.

## What `mcm upgrade` does

```
mcm upgrade [--config-root PATH] [--manager-source URL] [--template-source URL] [--dry-run] [--yes]
```

1. Downloads the latest `manager.lock` values (version + per-platform checksums) from `--manager-source`'s latest GitHub release (default: this repo, `p-victor/machine-config-manager`).
2. Downloads the latest `install.sh` and `config` from `--template-source` (default: `machine-config`'s `template/` on `main`) — these are authored there, not published as release assets here, since their bootstrap logic isn't really tied to any one manager release the way the binary/checksums are.
3. Re-applies whatever repo URL is already baked into your current `install.sh` (from `config init`, or a previous `upgrade`) onto the newly-fetched one — an upgrade updates the manager's own logic, it doesn't reset which personal config repo `install.sh` belongs to.
4. Diffs all three files against what's currently in your config repo. Nothing changed anywhere → prints `Already up to date.` and stops.
5. Prints the version change (`MANAGER_RELEASE` old → new) and a line-level diff of everything that changed, so you can see exactly what you're about to apply — this is deliberately not a silent overwrite.
6. `--dry-run` stops here. Otherwise, confirms (`--yes` skips the prompt), then writes all three files and re-marks `install.sh`/`config` executable.

Sample output:

```
$ mcm upgrade --config-root ~/.local/share/machine-config/repo

Upgrade

Config root:      /home/you/.local/share/machine-config/repo
Manager source:   https://github.com/p-victor/machine-config-manager
Template source:  https://raw.githubusercontent.com/p-victor/machine-config/main/template

Fetching latest manager.lock
Fetching latest install.sh/config

Manager release: v0.1.0 -> v0.2.0

Changes:
  manager.lock:
    - MANAGER_RELEASE="v0.1.0"
    - MANAGER_SHA256_LINUX_X86_64="cbda2bc6..."
    + MANAGER_RELEASE="v0.2.0"
    + MANAGER_SHA256_LINUX_X86_64="a1f9e02c..."

Apply this upgrade? [y/N]: y
Upgraded. Review the changes, commit, and push.
```

The diff shown is a line-set comparison (lines only in the old version, lines only in the new version), not a true positional/unified diff — there's no dependency on the `diff` binary, and for files this size (a few KB, changing rarely) it's enough to see what actually changed without needing alignment.

## Forking the manager itself

If you want your own build of `machine-config-manager` — a patched command, different DSL behavior, whatever — `upgrade` (and the bootstrap scripts themselves) treat "where the manager release lives" as one plain configuration value, not something hardcoded to this repo:

```
mcm upgrade --manager-source https://github.com/YOU/machine-config-manager
```

For this to work, your fork needs to cut its own releases the same way this repo does — see [`scripts/release.sh`](../scripts/release.sh) and [`.github/workflows/release.yml`](../.github/workflows/release.yml). Both are plain scripts/config, not tied to GitHub Actions specifically: `scripts/release.sh` is what actually builds and checksums a release (works under any CI, or by hand), and the workflow just invokes it on tag push. Cut a release the same way (a GitHub release tagged `vX.Y.Z` with `mcm-linux-x86_64`, `mcm-linux-x86_64.sha256`, `mcm-linux-aarch64`, `mcm-linux-aarch64.sha256`, and `manager.lock.fragment` as assets) and `--manager-source` will fetch from it exactly like the real thing.

If you're also forking `install.sh`/`config`'s own logic (not just the manager binary), point `--template-source` at your fork's raw content the same way:

```
mcm upgrade --manager-source https://github.com/YOU/machine-config-manager \
            --template-source https://raw.githubusercontent.com/YOU/machine-config/main/template
```

## Building from source instead of trusting a release binary

`install.sh`/`config` download a prebuilt binary and verify its checksum — that's the whole trust model for the common case. If you'd rather not trust a binary release at all, this repo is normal [C3](https://c3-lang.org/) source: clone it, `c3c build`, and use the resulting `build/mcm` directly (symlink it in place of what `install.sh` would have fetched, or just run it with `--config-root` pointed at your config repo). Nothing about `install.sh`/`config`'s bootstrap requires the binary specifically come from a GitHub release — only that it exists, is executable, and matches what `manager.lock` expects (which doesn't apply if you're bypassing the checksum step entirely by building your own).
