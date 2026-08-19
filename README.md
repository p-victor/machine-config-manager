# machine-config-manager

The compiled manager binary for
[machine-config](https://github.com/p-victor/machine-config), written in
[C3](https://c3-lang.org/).

`machine-config` deliberately has zero runtime dependencies beyond Bash +
git + curl-or-wget + tar, so a bare machine can bootstrap itself with
nothing else installed. That property doesn't change here — it just moves
where the boundary sits:

- `machine-config`'s `template/install.sh` stays a tiny POSIX/Bash bootstrap
  script: it clones your personal config repo, reads `manager.lock`,
  downloads the platform-matching prebuilt binary from this repo's GitHub
  Releases, verifies its checksum, and execs it.
- Everything past that point — the `install`/`doctor`/`publish`/`validate`/
  `status`/`diff` commands, and the environment/module DSL parser — lives
  here as a single compiled binary, replacing the ~8k lines of Bash
  previously implementing them directly in `machine-config`.

The DSL itself (environments and modules, currently expressed as
`mod_id "shell"` / `env_enable_module "git"`-style Bash function calls in
`machine-config`'s `environments/*.sh` and `modules/*/module.sh`) is being
redesigned here as a real parsed grammar rather than sourced Bash. See
`machine-config`'s `docs/module-authoring.md` and
`docs/environment-authoring.md` for the semantics this replaces.

## Status

Early scaffolding. No parser, no ported command logic yet.

## Building

```bash
c3c build
```

Requires the [C3 compiler](https://github.com/c3lang/c3c) (`c3c`).
