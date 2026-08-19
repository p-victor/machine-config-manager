module machine_config_manager::git;
import std::io;
import std::io::path;
import std::os::process;
import std::collections::list;

<*
 True if `git` is on PATH and actually runs. The one place every
 git-optional command (status/diff/publish) should check before doing
 anything else git-shaped — see docs/upgrading.md's design note: git is
 never a hard dependency, only an enhancement offered/checked for at the
 point a command actually wants it.
*>
fn bool is_available()
{
    if (catch process::run({ "git", "--version" })) return false;
    return true;
}

fn bool is_repo(String path_str)
{
    return path::is_dir(path::tnew(string::tformat("%s/.git", path_str)) ?? (Path)"");
}

<*
 Streams `git diff`'s own output straight to this process's stdout/stderr
 (INHERIT_STDIO — a diff can be arbitrarily large, unlike the small,
 known-bounded output current_branch/uncommitted_count capture into a
 fixed buffer) and returns its exit status. Thin on purpose: the point is
 showing exactly what `git diff` would show, not reimplementing it — same
 rationale as commands/diff.sh in the Bash implementation.
*>
fn int? diff(String repo_path)
{
    return process::run({ "git", "-C", repo_path, "diff" }, process::SpawnOptions.INHERIT_STDIO);
}

<*
 Current branch name, or "" if detached/unborn. Caller must have already
 checked is_available()/is_repo() — this doesn't re-check either, same
 division of responsibility as the Bash implementation's status/diff
 commands (they gate on mc_require_cmd/`-d .git` once up front, not per
 git invocation).
*>
fn String? current_branch(String repo_path)
{
    char[1024] buf;
    String out = process::run_capture_stdout(&buf, { "git", "-C", repo_path, "branch", "--show-current" })!;
    // out slices into `buf`, a local about to go out of scope — copy into
    // tmem so it's still valid once the caller reads the returned String.
    return out.trim().tcopy();
}

<*
 Count of changed/untracked paths (one line of `git status --porcelain`
 per path) — same number lib/git.sh's mc_git_repo_uncommitted_count
 reports.
*>
fn int? uncommitted_count(String repo_path)
{
    char[65536] buf;
    String out = process::run_capture_stdout(&buf, { "git", "-C", repo_path, "status", "--porcelain", "--untracked-files=all" })!;
    int count = 0;
    foreach (line : out.tsplit("\n"))
    {
        if (line.trim().len > 0) count++;
    }
    return count;
}

<*
 Raw `git status --porcelain` output, copied into tmem (see
 current_branch's comment — same stack-buffer-lifetime reason).
*>
fn String? status_porcelain(String repo_path)
{
    char[65536] buf;
    String out = process::run_capture_stdout(&buf, { "git", "-C", repo_path, "status", "--porcelain", "--untracked-files=all" })!;
    return out.tcopy();
}

<*
 Parses `git status --porcelain` output into repo-relative changed paths.
 A rename ("old -> new") keeps only the new path. Same known
 simplification as commands/publish.sh's mc_publish_read_changed_files:
 doesn't handle quoted/escaped filenames from very unusual names.
*>
fn List{String} parse_changed_files(String porcelain_output)
{
    List{String} paths;
    paths.tinit();
    foreach (line : porcelain_output.tsplit("\n"))
    {
        if (line.len < 4) continue;
        String p = line[3..];
        sz? arrow = p.index_of(" -> ");
        if (try a = arrow) p = p[a + 4..];
        paths.push(p);
    }
    return paths;
}

fn int? add_all(String repo_path)
{
    return process::run({ "git", "-C", repo_path, "add", "-A" }, process::SpawnOptions.INHERIT_STDIO);
}

fn int? commit(String repo_path, String message)
{
    return process::run({ "git", "-C", repo_path, "commit", "--quiet", "-m", message }, process::SpawnOptions.INHERIT_STDIO);
}

fn bool has_remote(String repo_path)
{
    char[4096] buf;
    String? out = process::run_capture_stdout(&buf, { "git", "-C", repo_path, "remote" });
    if (catch out) return false;
    return out.trim().len > 0;
}

fn int? fetch(String repo_path)
{
    return process::run({ "git", "-C", repo_path, "fetch", "--quiet" }, process::SpawnOptions.INHERIT_STDIO);
}

<*
 Fast-forward only — never auto-resolves a conflict, never force-merges.
 A non-zero exit means the branches have diverged; the caller (publish)
 dies cleanly rather than attempting anything cleverer, same as
 commands/publish.sh's mc_publish_sync.
*>
fn int? merge_ff_only(String repo_path)
{
    return process::run({ "git", "-C", repo_path, "merge", "--ff-only", "FETCH_HEAD" }, process::SpawnOptions.INHERIT_STDIO);
}

<*
 Never force-pushes — a plain `git push`, so a rejected push (e.g. the
 remote moved after fetch/merge above) surfaces as a normal failure
 instead of being overridden.
*>
fn int? push(String repo_path)
{
    return process::run({ "git", "-C", repo_path, "push" }, process::SpawnOptions.INHERIT_STDIO);
}
