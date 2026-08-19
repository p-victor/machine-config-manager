module machine_config_manager::dsl;
import std::io;

fn void test_manual_task_full() @test
{
    String src = string::tformat(
        "TASK vscode-sync\n"
        "DESCRIPTION Sign into VS Code Settings Sync\n"
        "OPTIONAL\n"
        "INSTRUCTIONS Open VS Code, click your account icon, and sign in.\n"
    );
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 0);
    test::eq(p.tasks.len(), 1);
    test::eq(p.tasks[0].id, "vscode-sync");
    test::eq(p.tasks[0].description, "Sign into VS Code Settings Sync");
    test::eq(p.tasks[0].required, false);
    test::eq(p.tasks[0].instructions, "Open VS Code, click your account icon, and sign in.");
    test::eq(p.tasks[0].verify, "");
}

fn void test_manual_task_required_and_verify() @test
{
    String src = "TASK dotfiles-review\nDESCRIPTION Review dotfiles before publishing\nREQUIRED\nVERIFY -- test -f ~/.reviewed\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 0);
    test::eq(p.tasks[0].required, true);
    test::eq(p.tasks[0].verify, "test -f ~/.reviewed");
}

fn void test_manual_task_multiple_tasks_in_one_file() @test
{
    String src = string::tformat(
        "TASK first\n"
        "DESCRIPTION First task\n"
        "TASK second\n"
        "DESCRIPTION Second task\n"
        "REQUIRED\n"
    );
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 0);
    test::eq(p.tasks.len(), 2);
    test::eq(p.tasks[0].id, "first");
    test::eq(p.tasks[0].required, false);
    test::eq(p.tasks[1].id, "second");
    test::eq(p.tasks[1].required, true);
}

fn void test_manual_task_empty_file_is_empty_not_error() @test
{
    ManualTasksParse p = parse_manual_tasks("");
    test::eq(p.errors.len(), 0);
    test::eq(p.tasks.len(), 0);
}

fn void test_manual_task_missing_description() @test
{
    String src = "TASK foo\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 1);
    test::eq(p.tasks.len(), 0);
    test::@check(p.errors[0].contains("no DESCRIPTION"), "got: %s", p.errors[0]);
}

fn void test_manual_task_invalid_id() @test
{
    String src = "TASK Not_Valid\nDESCRIPTION x\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 1);
    test::eq(p.tasks.len(), 0);
}

fn void test_manual_task_duplicate_id() @test
{
    String src = "TASK dup\nDESCRIPTION one\nTASK dup\nDESCRIPTION two\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 1);
    test::eq(p.tasks.len(), 1);
    test::@check(p.errors[0].contains("duplicate task id"), "got: %s", p.errors[0]);
}

fn void test_manual_task_field_before_any_task() @test
{
    String src = "DESCRIPTION orphaned\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 1);
    test::@check(p.errors[0].contains("before any TASK"), "got: %s", p.errors[0]);
}

fn void test_manual_task_verify_requires_dashdash() @test
{
    String src = "TASK x\nDESCRIPTION x\nVERIFY test -f foo\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 1);
    test::@check(p.errors[0].contains("-- COMMAND"), "got: %s", p.errors[0]);
}

fn void test_manual_task_unknown_keyword() @test
{
    String src = "TASK x\nDESCRIPTION x\nBOGUS y\n";
    ManualTasksParse p = parse_manual_tasks(src);
    test::eq(p.errors.len(), 1);
    test::@check(p.errors[0].contains("unknown keyword"), "got: %s", p.errors[0]);
}
