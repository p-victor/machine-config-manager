module machine_config_manager::local_values;
import std::io;

fn void test_parse_basic() @test
{
    LocalValues v = parse("GIT_NAME=Victor Poirier\nGIT_EMAIL=x@example.com\n");
    test::eq(v.len(), 2);
    test::eq(v.get("GIT_NAME")!!, "Victor Poirier");
    test::eq(v.get("GIT_EMAIL")!!, "x@example.com");
}

fn void test_parse_skips_comments_and_blanks() @test
{
    LocalValues v = parse("# a comment\n\nEDITOR=nvim\n");
    test::eq(v.len(), 1);
    test::eq(v.get("EDITOR")!!, "nvim");
}

fn void test_parse_skips_malformed_lines() @test
{
    LocalValues v = parse("not a valid line\nEDITOR=nvim\n");
    test::eq(v.len(), 1);
}

fn void test_parse_empty_value() @test
{
    LocalValues v = parse("EMPTY=\n");
    test::eq(v.len(), 1);
    test::eq(v.get("EMPTY")!!, "");
}

fn void test_parse_last_write_wins_on_duplicate() @test
{
    LocalValues v = parse("EDITOR=vim\nEDITOR=nvim\n");
    test::eq(v.len(), 1);
    test::eq(v.get("EDITOR")!!, "nvim");
}

fn void test_format_line() @test
{
    test::eq(format_line("EDITOR", "nvim"), "EDITOR=nvim\n");
}

fn void test_load_missing_file_is_empty() @test
{
    LocalValues v = load("test/fixtures/does-not-exist.env");
    test::eq(v.len(), 0);
}
