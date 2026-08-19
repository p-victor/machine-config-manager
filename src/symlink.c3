module machine_config_manager::symlink;
import std::io;
import std::io::path;
import std::os::process;
import std::time;
import std::time::datetime;

<*
 One symlink deployment outcome — same vocabulary as lib/symlink.sh's
 mc_symlink_report: exactly one of these per target, "backed_up" and
 "linked" both appearing (as two Result entries) when a real file
 conflicted and had to be moved aside first.
*>
enum Status
{
    CREATED,
    LINKED,
    UPDATED,
    UNCHANGED,
    SKIPPED,
    BACKED_UP,
    FAILED,
}

struct Result
{
    String target;
    Status status;
    String detail; // e.g. the backup path, or the source it now points at
}

<*
 No dedicated symlink/readlink binding in the C3 std — shells out to
 `test -L`/`readlink`, same primitive-delegation choice already made for
 chmod (local_values.c3) and every platform tool this project wraps
 rather than reimplements.
*>
fn bool is_symlink(String target)
{
    int? r = process::run({ "test", "-L", target });
    if (catch r) return false;
    return r == 0;
}

fn String? read_link(String target)
{
    char[4096] buf;
    String out = process::run_capture_stdout(&buf, { "readlink", "--", target })!;
    return out.trim().tcopy();
}

<*
 True if `target` is a symlink pointing exactly at `source`. Read-only —
 for a future `doctor`-style check that must never write, same role as
 lib/symlink.sh's mc_symlink_matches.
*>
fn bool matches(String source, String target)
{
    if (!is_symlink(target)) return false;
    String? current = read_link(target);
    if (catch current) return false;
    return current == source;
}

fn String backup_path(String target)
{
    DateTime dt = datetime::now();
    return string::tformat("%s.backup.%04d-%02d-%02dT%02d%02d%02d",
        target, dt.year, dt.month.ordinal + 1, (int)dt.day, (int)dt.hour, (int)dt.min, (int)dt.sec);
}

<*
 Moves `target` (file, directory, or symlink) to a timestamped backup
 path. Errors loudly if the computed backup path already exists rather
 than silently overwriting it — same refusal as lib/backup.sh's
 mc_backup_create (a same-second re-run is the realistic way to hit this,
 and guessing which one should win is worse than just stopping).
*>
faultdef BACKUP_DESTINATION_EXISTS;

fn String? create_backup(String target)
{
    String backup = backup_path(target);
    if (path::exists(path::tnew(backup) ?? (Path)"")) return BACKUP_DESTINATION_EXISTS~;
    process::run({ "mv", "--", target, backup })!;
    return backup;
}

<*
 Ensures `target` is a symlink to `source` (both expected absolute —
 callers own turning a relative module path into one; links are always
 absolute, never relative, since the repo's location is a fixed, known
 path). `dry_run` reports what would happen without touching the
 filesystem. Always returns a Result rather than a fault: a caller
 deploying many links across a module should keep going on one failure,
 not abort the whole batch — same contract as lib/symlink.sh's
 mc_symlink_deploy (its "return 1 on failure, still keep going" note).
*>
fn Result deploy(String source, String target, bool dry_run = false)
{
    if (is_symlink(target))
    {
        String? current = read_link(target);
        if (try c = current)
        {
            if (c == source) return { target, UNCHANGED, "" };
        }
        if (dry_run) return { target, SKIPPED, string::tformat("would update -> %s", source) };
        if (catch process::run({ "rm", "--", target }))
        {
            return { target, FAILED, "" };
        }
        if (catch process::run({ "ln", "-s", "--", source, target }))
        {
            return { target, FAILED, "" };
        }
        return { target, UPDATED, source };
    }

    if (path::exists(path::tnew(target) ?? (Path)""))
    {
        if (dry_run) return { target, SKIPPED, string::tformat("would back up and link -> %s", source) };
        String? backup = create_backup(target);
        if (catch backup)
        {
            return { target, FAILED, "" };
        }
        if (catch process::run({ "ln", "-s", "--", source, target }))
        {
            return { target, FAILED, "" };
        }
        // Two outcomes for one target, same as the Bash implementation's
        // two-line "backed up" + "linked" report — callers wanting a
        // single combined status can check .detail's presence instead.
        return { target, LINKED, string::tformat("backed up to %s, linked -> %s", backup, source) };
    }

    if (dry_run) return { target, SKIPPED, string::tformat("would link -> %s", source) };
    String? dir = target.path_tdirname();
    if (try d = dir)
    {
        if (catch path::mkdir(d, true))
        {
            return { target, FAILED, "" };
        }
    }
    if (catch process::run({ "ln", "-s", "--", source, target }))
    {
        return { target, FAILED, "" };
    }
    return { target, LINKED, source };
}
