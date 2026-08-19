module machine_config_manager::git_identity;
import std::io;
import std::io::path;
import std::io::file;

fn String workspace(String name)
{
    String dir = string::tformat("/tmp/mcm-git-identity-test-%s", name);
    (void)path::rmtree(path::tnew(dir)!!);
    (void)path::mkdir(dir, true);
    return dir;
}

fn void test_render_identity() @test
{
    test::eq(render_identity("Victor Poirier", "x@example.com"), "[user]\n    name = Victor Poirier\n    email = x@example.com\n");
}

fn void test_ensure_identity_created_then_unchanged_then_updated() @test
{
    String dir = workspace("flow");
    String f = string::tformat("%s/local.inc", dir);

    Status s1 = ensure_identity("Victor", "v@example.com", f)!!;
    test::eq(s1, Status.CREATED);
    test::eq(identity_matches("Victor", "v@example.com", f), true);

    Status s2 = ensure_identity("Victor", "v@example.com", f)!!;
    test::eq(s2, Status.UNCHANGED);

    Status s3 = ensure_identity("Victor", "new@example.com", f)!!;
    test::eq(s3, Status.UPDATED);
    test::eq(identity_matches("Victor", "new@example.com", f), true);
    test::eq(identity_matches("Victor", "v@example.com", f), false);
}

fn void test_ensure_identity_creates_parent_directory() @test
{
    String dir = workspace("parents");
    String f = string::tformat("%s/a/b/local.inc", dir);
    Status s = ensure_identity("V", "v@e.com", f)!!;
    test::eq(s, Status.CREATED);
    test::eq(path::exists(path::tnew(f)!!), true);
}

fn void test_identity_matches_false_for_missing_file() @test
{
    String dir = workspace("missing");
    test::eq(identity_matches("V", "v@e.com", string::tformat("%s/local.inc", dir)), false);
}

fn void test_identity_has_name_and_email() @test
{
    String dir = workspace("has-fields");
    String f = string::tformat("%s/local.inc", dir);
    (void)ensure_identity("Victor", "v@example.com", f);
    test::eq(identity_has_name(f), true);
    test::eq(identity_has_email(f), true);
}

fn void test_identity_has_name_false_when_missing() @test
{
    String dir = workspace("no-fields");
    String f = string::tformat("%s/local.inc", dir);
    file::save(f, "[user]\n")!!;
    test::eq(identity_has_name(f), false);
    test::eq(identity_has_email(f), false);
}
