module machine_config_manager::manual_tasks;
import machine_config_manager::dsl;
import machine_config_manager::xdg;
import std::io;
import std::io::file;
import std::io::path;
import std::os::process;
import std::collections::list;

enum Status
{
    DONE,
    PENDING,
}

<*
 A task with a VERIFY command is always live-checked — its status is
 never read from stored state (spec: prefer live verification over
 manually marked completion). A task with none (nothing reliably
 checkable, e.g. "sign into Settings Sync") falls back to XDG-state-backed
 manual marking. Same split as lib/manual_tasks.sh's mc_manual_task_status.
*>
fn Status status(dsl::ManualTaskDecl* task, String state_file_path)
{
    if (task.verify.len > 0)
    {
        int? r = process::run({ "bash", "-c", task.verify });
        if (catch r) return PENDING;
        return r == 0 ? DONE : PENDING;
    }
    return is_marked_done(task.id, state_file_path) ? DONE : PENDING;
}

fn String default_state_file() => xdg::manual_tasks_state_file();

fn bool is_marked_done(String id, String state_file_path)
{
    char[]? raw = file::load_temp(state_file_path);
    if (catch raw) return false;
    foreach (line : ((String)raw).tsplit("\n"))
    {
        if (line.trim() == id) return true;
    }
    return false;
}

<* Idempotent. Creates the state file/parent directory if needed. *>
fn void? mark_done(String id, String state_file_path)
{
    if (is_marked_done(id, state_file_path)) return;
    String? dir = state_file_path.path_tdirname();
    if (try d = dir) (void)path::mkdir(d, true);
    File f = file::open(state_file_path, "a")!;
    defer (void)f.close();
    (void)f.write(string::tformat("%s\n", id));
}

<*
 True if any REQUIRED task is still pending. Informational only — never
 fails install/validate itself, by definition these are things the
 manager can't do for the user.
*>
fn bool has_pending_required(dsl::ManualTaskDecl[] tasks, String state_file_path)
{
    foreach (t : tasks)
    {
        if (!t.required) continue;
        if (status(&t, state_file_path) == PENDING) return true;
    }
    return false;
}

<*
 Renders the checklist in registration order (caller decides that order —
 typically built-ins first, then module-declared). No-ops if `tasks` is
 empty. Simplified from lib/manual_tasks.sh's version: always uses an
 ASCII "x" for done rather than a Unicode check mark with a terminal-
 capability-detected fallback (that detection isn't ported).
*>
fn void render_checklist(dsl::ManualTaskDecl[] tasks, String state_file_path, String heading = "Post-install checklist")
{
    if (tasks.len == 0) return;
    io::printn(heading);
    io::printn("");
    foreach (t : tasks)
    {
        Status s = status(&t, state_file_path);
        String glyph = s == DONE ? "x" : " ";
        io::printfn("[%s] %s", glyph, t.description);
        if (s == PENDING && t.instructions.len > 0)
        {
            io::printfn("    %s", t.instructions);
        }
    }
}

<*
 modules/<id>/instructions/tasks.mcm, if present — empty parse (no
 tasks, no errors) if the file doesn't exist, same "optional file" model
 as checks/doctor.mcm would have used.
*>
fn dsl::ManualTasksParse discover_module_tasks(String module_dir)
{
    String file_path = string::tformat("%s/instructions/tasks.mcm", module_dir);
    char[]? raw = file::load_temp(file_path);
    if (catch raw)
    {
        dsl::ManualTasksParse empty;
        empty.tasks.tinit();
        empty.errors.tinit();
        return empty;
    }
    return dsl::parse_manual_tasks((String)raw);
}

// --- Built-in core tasks (not tied to any module) ---

// Verify commands are plain shell, executed standalone via `bash -c` —
// they must not assume any of this project's own state, only $HOME/
// $XDG_* and standard tools. Ported verbatim from
// lib/manual_tasks.sh's MC_TASK_BUILTIN_GIT_VERIFY/_SSH_VERIFY.
const String BUILTIN_GIT_VERIFY = `f="${XDG_CONFIG_HOME:-$HOME/.config}/git/local.inc"; [[ -f "$f" ]] && grep -Eq "^ *name = \S" "$f" && grep -Eq "^ *email = \S" "$f"`;
const String BUILTIN_SSH_VERIFY = `ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"`;

fn dsl::ManualTaskDecl builtin_git_identity() => {
    "git-identity",
    "Set your Git identity (name and email)",
    true,
    BUILTIN_GIT_VERIFY,
    "Set GIT_NAME and GIT_EMAIL (you'll be prompted automatically if your environment requires them).",
};

fn dsl::ManualTaskDecl builtin_github_ssh_key() => {
    "github-ssh-key",
    "Add your SSH public key to GitHub",
    false,
    BUILTIN_SSH_VERIFY,
    "Copy your public key: cat ~/.ssh/id_ed25519.pub\nAdd it at: https://github.com/settings/keys\nTest with: ssh -T git@github.com",
};
