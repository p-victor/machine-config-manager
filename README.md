# machine-config-manager

The compiled manager binary for
[machine-config](https://github.com/p-victor/machine-config), written in
[C3](https://c3-lang.org/).

`machine-config` deliberately has zero *hard* runtime dependencies beyond
Bash + curl-or-wget + tar, so a bare machine can bootstrap itself with
nothing else installed — not even git. That property doesn't change here
— it just moves where the boundary sits:

- `machine-config`'s `template/install.sh` stays a tiny POSIX/Bash
  bootstrap script: it downloads your personal config repo and the
  platform-matching prebuilt binary from this repo's GitHub Releases (both
  plain HTTPS tarball/binary fetches, no git clone anywhere), verifies the
  binary's checksum, and execs it.
- Everything past that point — the `install`/`publish`/`validate`/
  `status`/`diff`/`upgrade` commands, and the environment/module DSL
  parser — lives here as a single compiled binary, replacing the ~8k lines
  of Bash previously implementing them directly in `machine-config`. Git
  becomes optional: `publish`/`diff`/`status` use it when it's present and
  degrade gracefully when it isn't, instead of hard-requiring it.

The DSL itself (environments and modules, previously `mod_id "shell"` /
`env_enable_module "git"`-style Bash function calls in `machine-config`'s
`environments/*.sh` and `modules/*/module.sh`) is a real parsed grammar
here instead of sourced Bash: `.mcm` files, one instruction per line,
Docker-flavored (`ID`/`NAME`/`SUPPORTS`/`REQUIRES`/`LINK`/`FROM` for
modules; `ID`/`EXTENDS`/`ENABLE`/`REQUIRE_LOCAL` for environments — `FROM`
is new, Docker-style single-parent module inheritance the Bash DSL never
had). Module/environment ids are inferred from their path (directory name
/ filename) rather than declared. See `machine-config`'s
`docs/module-authoring.md` and `docs/environment-authoring.md` for the
semantics this replaces.

## Status

`validate`/`status`/`diff`/`publish`/`install`/`upgrade` are implemented —
discovery, `FROM`/`EXTENDS`/`REQUIRES` resolution with cycle/conflict
detection, platform detection, package management (pacman/apt/AUR), file
deployment, local values, Git identity, SSH key setup, the manual-task
checklist, and re-fetching/diffing/applying the latest `install.sh`/
`config`/`manager.lock` (see [`docs/upgrading.md`](docs/upgrading.md)).
`doctor` is out of scope for now. `init` (fetching a personal config repo
directly, for the package-manager install path — see `docs/upgrading.md`'s
sibling note in the original design plan) isn't built yet.

Releases are published from this repo — see
[Releases](https://github.com/p-victor/machine-config-manager/releases)
for the real, current binaries `install.sh`/`config` fetch. You won't
normally download one by hand: `machine-config`'s bootstrap does it for
you (see that repo's README for the actual end-user quick start).

## Building

```bash
c3c build   # -> build/mcm, statically linked
c3c test
```

Requires the [C3 compiler](https://github.com/c3lang/c3c) (`c3c`).
Cross-compiling for another target (see `.github/workflows/release.yml`,
which builds every release this way):

```bash
scripts/release.sh linux-aarch64 aarch64-linux-gnu-gcc
```
