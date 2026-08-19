module machine_config_manager::package_apt;
import std::os::process;
import std::collections::list;

fn bool is_installed(String name)
{
    char[1024] buf;
    String? out = process::run_capture_stdout(&buf, { "dpkg-query", "-W", "-f=${Status}", "--", name });
    if (catch out) return false;
    return out.contains("install ok installed");
}

<* Mutates the real system — never called from tests. *>
fn int? update()
{
    return process::run({ "sudo", "apt-get", "update" }, process::SpawnOptions.INHERIT_STDIO);
}

<*
 DEBIAN_FRONTEND=noninteractive skips apt's own prompts (e.g. config-file
 conflicts defaulting to keep-current) — the caller is expected to have
 already confirmed the plan with the user before calling this. Mutates
 the real system — never called from tests.
*>
fn int? install(String[] names)
{
    if (names.len == 0) return 0;
    List{String} cmd;
    cmd.tinit();
    cmd.push_all({ "sudo", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "--" });
    cmd.push_all(names);
    return process::run(cmd.to_tarray(), process::SpawnOptions.INHERIT_STDIO);
}
