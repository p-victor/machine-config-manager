module machine_config_manager::package_pacman;
import std::os::process;
import std::collections::list;

fn bool is_installed(String name)
{
    int? r = process::run({ "pacman", "-Qq", "--", name });
    if (catch r) return false;
    return r == 0;
}

<*
 Full system upgrade — refreshes the package database and upgrades in one
 step, never a bare `-Sy` (that alone can leave a broken partial-upgrade
 state if packages are then installed against a newer db against older
 installed versions). Mutates the real system — never called from tests.
*>
fn int? sync()
{
    return process::run({ "sudo", "pacman", "-Syu", "--noconfirm" }, process::SpawnOptions.INHERIT_STDIO);
}

<*
 Installs (or no-ops if already installed, via --needed). --noconfirm
 skips pacman's own transaction prompt — the caller is expected to have
 already confirmed the plan with the user before calling this. Mutates
 the real system — never called from tests.
*>
fn int? install(String[] names)
{
    if (names.len == 0) return 0;
    List{String} cmd;
    cmd.tinit();
    cmd.push_all({ "sudo", "pacman", "-S", "--needed", "--noconfirm", "--" });
    cmd.push_all(names);
    return process::run(cmd.to_tarray(), process::SpawnOptions.INHERIT_STDIO);
}
