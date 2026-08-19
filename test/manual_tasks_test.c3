module machine_config_manager::manual_tasks;
import machine_config_manager::dsl;
import std::io;
import std::io::path;
import std::io::file;
import std::collections::list;

fn String workspace(String name)
{
    String dir = string::tformat("/tmp/mcm-manual-tasks-test-%s", name);
    (void)path::rmtree(path::tnew(dir)!!);
    (void)path::mkdir(dir, true);
    return dir;
}

fn dsl::ManualTaskDecl mk_task(String id, bool required = false, String verify = "", String instructions = "")
{
    return { id, string::tformat("Description of %s", id), required, verify, instructions };
}

fn void test_status_no_verify_falls_back_to_state_file() @test
{
    String dir = workspace("state-fallback");
    String state_file = string::tformat("%s/manual_tasks_done", dir);
    dsl::ManualTaskDecl t = mk_task("settings-sync");

    test::eq(status(&t, state_file), Status.PENDING);
    (void)mark_done("settings-sync", state_file);
    test::eq(status(&t, state_file), Status.DONE);
}

fn void test_mark_done_is_idempotent() @test
{
    String dir = workspace("idempotent");
    String state_file = string::tformat("%s/manual_tasks_done", dir);

    (void)mark_done("x", state_file);
    (void)mark_done("x", state_file);
    (void)mark_done("x", state_file);

    char[] raw = file::load_temp(state_file)!!;
    String content = (String)raw;
    int count = 0;
    foreach (line : content.tsplit("\n"))
    {
        if (line.trim() == "x") count++;
    }
    test::eq(count, 1);
}

fn void test_status_verify_true_is_done() @test
{
    String dir = workspace("verify-true");
    dsl::ManualTaskDecl t = mk_task("always-true", false, "true");
    test::eq(status(&t, string::tformat("%s/state", dir)), Status.DONE);
}

fn void test_status_verify_false_is_pending() @test
{
    String dir = workspace("verify-false");
    dsl::ManualTaskDecl t = mk_task("always-false", false, "false");
    test::eq(status(&t, string::tformat("%s/state", dir)), Status.PENDING);
}

fn void test_status_verify_ignores_state_file_even_if_marked() @test
{
    // A VERIFY command always wins — never falls back to stored state,
    // even if the id happens to be marked done there.
    String dir = workspace("verify-wins");
    String state_file = string::tformat("%s/manual_tasks_done", dir);
    (void)mark_done("checked-live", state_file);

    dsl::ManualTaskDecl t = mk_task("checked-live", false, "false");
    test::eq(status(&t, state_file), Status.PENDING);
}

fn void test_has_pending_required_true() @test
{
    String dir = workspace("pending-required-true");
    dsl::ManualTaskDecl[] tasks = { mk_task("a", true, "false"), mk_task("b", false, "false") };
    test::eq(has_pending_required(tasks, string::tformat("%s/state", dir)), true);
}

fn void test_has_pending_required_false_when_only_optional_pending() @test
{
    String dir = workspace("pending-required-false");
    dsl::ManualTaskDecl[] tasks = { mk_task("a", true, "true"), mk_task("b", false, "false") };
    test::eq(has_pending_required(tasks, string::tformat("%s/state", dir)), false);
}

fn void test_discover_module_tasks_missing_file_is_empty() @test
{
    String dir = workspace("no-tasks-file");
    dsl::ManualTasksParse p = discover_module_tasks(dir);
    test::eq(p.tasks.len(), 0);
    test::eq(p.errors.len(), 0);
}

fn void test_discover_module_tasks_reads_real_file() @test
{
    String dir = workspace("has-tasks-file");
    (void)path::mkdir(string::tformat("%s/instructions", dir), true);
    file::save(string::tformat("%s/instructions/tasks.mcm", dir), "TASK t1\nDESCRIPTION Do the thing\n")!!;

    dsl::ManualTasksParse p = discover_module_tasks(dir);
    test::eq(p.errors.len(), 0);
    test::eq(p.tasks.len(), 1);
    test::eq(p.tasks[0].id, "t1");
}

fn void test_builtin_git_identity_shape() @test
{
    dsl::ManualTaskDecl t = builtin_git_identity();
    test::eq(t.id, "git-identity");
    test::eq(t.required, true);
    test::@check(t.verify.len > 0, "expected a live VERIFY command");
}

fn void test_builtin_github_ssh_key_shape() @test
{
    dsl::ManualTaskDecl t = builtin_github_ssh_key();
    test::eq(t.id, "github-ssh-key");
    test::eq(t.required, false);
    test::@check(t.verify.len > 0, "expected a live VERIFY command");
}
