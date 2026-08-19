module machine_config_manager::symlink;
import std::io;
import std::io::path;
import std::io::file;

<*
 Fresh, empty scratch directory for one test — removed first if a
 previous run left it behind, so tests don't interfere with each other
 even though they share /tmp.
*>
fn String workspace(String name)
{
    String dir = string::tformat("/tmp/mcm-symlink-test-%s", name);
    (void)path::rmtree(path::tnew(dir)!!);
    (void)path::mkdir(dir, true);
    return dir;
}

fn void test_backup_path_shape() @test
{
    String b = backup_path("/tmp/foo");
    test::@check(b.starts_with("/tmp/foo.backup."), "got: %s", b);
    test::@check(b.len > "/tmp/foo.backup.".len, "expected a timestamp suffix, got: %s", b);
}

fn void test_deploy_fresh_target_creates_link() @test
{
    String dir = workspace("fresh");
    String source = string::tformat("%s/source-file", dir);
    String target = string::tformat("%s/target-link", dir);
    file::save(source, "hello")!!;

    Result r = deploy(source, target);
    test::eq(r.status, Status.LINKED);
    test::eq(r.detail, source);
    test::eq(is_symlink(target), true);
    test::eq(read_link(target)!!, source);
}

fn void test_deploy_creates_parent_directories() @test
{
    String dir = workspace("parents");
    String source = string::tformat("%s/source-file", dir);
    String target = string::tformat("%s/a/b/c/target-link", dir);
    file::save(source, "hello")!!;

    Result r = deploy(source, target);
    test::eq(r.status, Status.LINKED);
    test::eq(is_symlink(target), true);
}

fn void test_deploy_second_call_is_unchanged() @test
{
    String dir = workspace("unchanged");
    String source = string::tformat("%s/source-file", dir);
    String target = string::tformat("%s/target-link", dir);
    file::save(source, "hello")!!;

    Result r1 = deploy(source, target);
    test::eq(r1.status, Status.LINKED);
    Result r2 = deploy(source, target);
    test::eq(r2.status, Status.UNCHANGED);
}

fn void test_deploy_updates_when_pointing_elsewhere() @test
{
    String dir = workspace("updates");
    String old_source = string::tformat("%s/old-source", dir);
    String new_source = string::tformat("%s/new-source", dir);
    String target = string::tformat("%s/target-link", dir);
    file::save(old_source, "old")!!;
    file::save(new_source, "new")!!;

    test::eq(deploy(old_source, target).status, Status.LINKED);
    Result r = deploy(new_source, target);
    test::eq(r.status, Status.UPDATED);
    test::eq(read_link(target)!!, new_source);
}

fn void test_deploy_backs_up_real_file_in_the_way() @test
{
    String dir = workspace("backup");
    String source = string::tformat("%s/source-file", dir);
    String target = string::tformat("%s/target", dir);
    file::save(source, "from module")!!;
    file::save(target, "pre-existing real file")!!;

    Result r = deploy(source, target);
    test::eq(r.status, Status.LINKED);
    test::@check(r.detail.contains("backed up to"), "got: %s", r.detail);
    test::eq(is_symlink(target), true);
    test::eq(read_link(target)!!, source);

    // The backup path is reported under the same workspace dir.
    test::@check(r.detail.contains(dir), "expected the workspace dir in detail: %s", r.detail);
}

fn void test_deploy_dry_run_never_touches_filesystem() @test
{
    String dir = workspace("dryrun");
    String source = string::tformat("%s/source-file", dir);
    String target = string::tformat("%s/target-link", dir);
    file::save(source, "hello")!!;

    Result r = deploy(source, target, true);
    test::eq(r.status, Status.SKIPPED);
    test::eq(path::exists(path::tnew(target)!!), false);
}

fn void test_matches_true_for_correct_link() @test
{
    String dir = workspace("matches-true");
    String source = string::tformat("%s/source-file", dir);
    String target = string::tformat("%s/target-link", dir);
    file::save(source, "hello")!!;
    (void)deploy(source, target);

    test::eq(matches(source, target), true);
}

fn void test_matches_false_for_non_symlink() @test
{
    String dir = workspace("matches-false");
    String target = string::tformat("%s/plain-file", dir);
    file::save(target, "not a link")!!;

    test::eq(matches(string::tformat("%s/whatever", dir), target), false);
}
