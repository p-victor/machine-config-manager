module machine_config_manager::xdg;
import std::os::env;

<*
 Centralized XDG Base Directory paths — single source of truth so they're
 computed once here instead of re-inlined wherever a command needs one,
 same rationale as lib/xdg.sh.
*>
fn String data_home()
{
    String? v = env::tget_var("XDG_DATA_HOME");
    if (try b = v) return b;
    String? home = env::tget_var("HOME");
    if (try h = home) return string::tformat("%s/.local/share", h);
    return "./.local/share";
}

fn String config_home()
{
    String? v = env::tget_var("XDG_CONFIG_HOME");
    if (try b = v) return b;
    String? home = env::tget_var("HOME");
    if (try h = home) return string::tformat("%s/.config", h);
    return "./.config";
}

fn String state_home()
{
    String? v = env::tget_var("XDG_STATE_HOME");
    if (try b = v) return b;
    String? home = env::tget_var("HOME");
    if (try h = home) return string::tformat("%s/.local/state", h);
    return "./.local/state";
}

<* The persistent personal config repo location. *>
fn String config_repo_root() => string::tformat("%s/machine-config/repo", data_home());

<* The machine-local, never-committed local values file. *>
fn String local_env_file() => string::tformat("%s/machine-config/local.env", config_home());

<* Persistent state (e.g. the saved default environment). *>
fn String state_dir() => string::tformat("%s/machine-config", state_home());

<* Manual tasks marked done via stored state (no VERIFY command). *>
fn String manual_tasks_state_file() => string::tformat("%s/manual_tasks_done", state_dir());

<*
 The last environment `install` was run against — read by `install` (as a
 selection default) and usable by a future `doctor`. Computed fresh each
 call rather than cached, same reason lib/xdg.sh's version is: a captured
 value would freeze whatever HOME/XDG vars were set at first call, wrong
 for test isolation.
*>
fn String saved_environment_file() => string::tformat("%s/default-environment", state_dir());

<* The machine-local Git identity include target (see docs on git_identity.c3). *>
fn String git_local_inc_path() => string::tformat("%s/git/local.inc", config_home());
