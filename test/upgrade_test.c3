module machine_config_manager::upgrade;
import std::io;

fn void test_extract_configured_repo_url_found() @test
{
    String content = "MC_CONFIG_REPO_DEFAULT_URL=\"https://github.com/victor/dotfiles\"\n";
    test::eq(extract_configured_repo_url(content)!!, "https://github.com/victor/dotfiles");
}

fn void test_extract_configured_repo_url_still_placeholder() @test
{
    String content = "MC_CONFIG_REPO_DEFAULT_URL=\"__MC_CONFIG_REPO_URL__\"\n";
    if (catch extract_configured_repo_url(content)) return; // expected
    test::@check(false, "expected NOT_YET_CONFIGURED");
}

fn void test_extract_configured_repo_url_missing_line() @test
{
    String content = "echo hello\n";
    if (catch extract_configured_repo_url(content)) return; // expected
    test::@check(false, "expected NOT_YET_CONFIGURED");
}

fn void test_apply_configured_repo_url() @test
{
    String content = "MC_CONFIG_REPO_DEFAULT_URL=\"__MC_CONFIG_REPO_URL__\"\n";
    String result = apply_configured_repo_url(content, "https://github.com/victor/dotfiles");
    test::eq(result, "MC_CONFIG_REPO_DEFAULT_URL=\"https://github.com/victor/dotfiles\"\n");
}

fn void test_line_diff_identical_is_empty() @test
{
    LineDiff d = line_diff("a\nb\nc\n", "a\nb\nc\n");
    test::eq(line_diff_is_empty(&d), true);
}

fn void test_line_diff_detects_changes() @test
{
    LineDiff d = line_diff("a\nb\nc\n", "a\nx\nc\n");
    test::eq(line_diff_is_empty(&d), false);
    test::eq(d.removed.len(), 1);
    test::eq(d.removed[0], "b");
    test::eq(d.added.len(), 1);
    test::eq(d.added[0], "x");
}

fn void test_line_diff_pure_addition() @test
{
    LineDiff d = line_diff("a\n", "a\nb\n");
    test::eq(d.removed.len(), 0);
    test::eq(d.added.len(), 1);
    test::eq(d.added[0], "b");
}

fn void test_extract_manager_release() @test
{
    String content = "MANAGER_VERSION=\"0.1.0\"\nMANAGER_RELEASE=\"v0.1.0\"\n";
    test::eq(extract_manager_release(content)!!, "v0.1.0");
}

fn void test_extract_manager_release_missing() @test
{
    if (catch extract_manager_release("nothing here\n")) return; // expected
    test::@check(false, "expected NOT_YET_CONFIGURED");
}
