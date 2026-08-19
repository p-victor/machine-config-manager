module machine_config_manager::git;
import std::io;
import std::collections::list;

fn void test_parse_changed_files_basic() @test
{
    String porcelain = " M modules/nvim/module.mcm\n?? environments/new.mcm\n";
    List{String} files = parse_changed_files(porcelain);
    test::eq(files.len(), 2);
    test::eq(files[0], "modules/nvim/module.mcm");
    test::eq(files[1], "environments/new.mcm");
}

fn void test_parse_changed_files_rename_keeps_new_path() @test
{
    String porcelain = "R  environments/old.mcm -> environments/new.mcm\n";
    List{String} files = parse_changed_files(porcelain);
    test::eq(files.len(), 1);
    test::eq(files[0], "environments/new.mcm");
}

fn void test_parse_changed_files_empty() @test
{
    List{String} files = parse_changed_files("");
    test::eq(files.len(), 0);
}

fn void test_parse_changed_files_skips_blank_lines() @test
{
    String porcelain = " M a.mcm\n\n?? b.mcm\n";
    List{String} files = parse_changed_files(porcelain);
    test::eq(files.len(), 2);
}
