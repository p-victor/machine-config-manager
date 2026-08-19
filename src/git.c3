module machine_config_manager::git;
import std::io;
import std::io::path;
import std::os::process;

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
