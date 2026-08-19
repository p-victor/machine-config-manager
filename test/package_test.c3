module machine_config_manager::package;
import std::io;
import std::io::path;
import std::io::file;
import std::collections::list;

fn String workspace(String name)
{
    String dir = string::tformat("/tmp/mcm-package-test-%s", name);
    (void)path::rmtree(path::tnew(dir)!!);
    (void)path::mkdir(dir, true);
    return dir;
}

fn void test_read_list_strips_comments_and_blanks() @test
{
    String dir = workspace("read-list");
    String f = string::tformat("%s/packages.arch", dir);
    file::save(f, "# a comment\n\nfd\nripgrep\n")!!;

    List{String} names = read_list(f);
    test::eq(names.len(), 2);
    test::eq(names[0], "fd");
    test::eq(names[1], "ripgrep");
}

fn void test_read_list_missing_file_is_empty() @test
{
    List{String} names = read_list("test/fixtures/does-not-exist.packages");
    test::eq(names.len(), 0);
}

fn void test_module_package_list_required_and_optional() @test
{
    String dir = workspace("module-list");
    file::save(string::tformat("%s/packages.arch", dir), "fd\nripgrep\n")!!;
    file::save(string::tformat("%s/packages.arch.optional", dir), "bat\n")!!;

    List{PackageRef} refs = module_package_list(dir, "arch");
    test::eq(refs.len(), 3);
    test::eq(refs[0].name, "fd");
    test::eq(refs[0].kind, Kind.REQUIRED);
    test::eq(refs[2].name, "bat");
    test::eq(refs[2].kind, Kind.OPTIONAL);
}

fn void test_plan_dedupes_across_modules() @test
{
    String base = workspace("plan-dedup");
    String mod_a = string::tformat("%s/a", base);
    String mod_b = string::tformat("%s/b", base);
    (void)path::mkdir(mod_a, true);
    (void)path::mkdir(mod_b, true);
    file::save(string::tformat("%s/packages.arch", mod_a), "shared\nonly-a\n")!!;
    file::save(string::tformat("%s/packages.arch", mod_b), "shared\nonly-b\n")!!;

    List{PackageRef} plan_result = plan({ mod_a, mod_b }, "arch");
    test::eq(plan_result.len(), 3); // shared, only-a, only-b — "shared" once
}

fn void test_plan_required_wins_over_optional() @test
{
    String base = workspace("plan-required-wins");
    String mod_a = string::tformat("%s/a", base);
    String mod_b = string::tformat("%s/b", base);
    (void)path::mkdir(mod_a, true);
    (void)path::mkdir(mod_b, true);
    // "shared" is optional for module a, required for module b.
    file::save(string::tformat("%s/packages.arch.optional", mod_a), "shared\n")!!;
    file::save(string::tformat("%s/packages.arch", mod_b), "shared\n")!!;

    List{PackageRef} plan_result = plan({ mod_a, mod_b }, "arch");
    test::eq(plan_result.len(), 1);
    test::eq(plan_result[0].kind, Kind.REQUIRED);
}

fn void test_plan_required_seen_first_stays_required() @test
{
    String base = workspace("plan-required-first");
    String mod_a = string::tformat("%s/a", base);
    String mod_b = string::tformat("%s/b", base);
    (void)path::mkdir(mod_a, true);
    (void)path::mkdir(mod_b, true);
    file::save(string::tformat("%s/packages.arch", mod_a), "shared\n")!!;
    file::save(string::tformat("%s/packages.arch.optional", mod_b), "shared\n")!!;

    List{PackageRef} plan_result = plan({ mod_a, mod_b }, "arch");
    test::eq(plan_result.len(), 1);
    test::eq(plan_result[0].kind, Kind.REQUIRED);
}

fn void test_plan_first_seen_order() @test
{
    String base = workspace("plan-order");
    String mod_a = string::tformat("%s/a", base);
    (void)path::mkdir(mod_a, true);
    file::save(string::tformat("%s/packages.arch", mod_a), "zzz\naaa\nmmm\n")!!;

    List{PackageRef} plan_result = plan({ mod_a }, "arch");
    test::eq(plan_result.len(), 3);
    test::eq(plan_result[0].name, "zzz");
    test::eq(plan_result[1].name, "aaa");
    test::eq(plan_result[2].name, "mmm");
}
