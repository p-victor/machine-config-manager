module machine_config_manager::security;
import std::io;
import std::collections::list;

fn void test_scan_content_clean() @test
{
    List{Finding} f = scan_content("just some ordinary config\nno secrets here\n", "x.mcm");
    test::eq(f.len(), 0);
}

fn void test_scan_content_private_key() @test
{
    List{Finding} f = scan_content("-----BEGIN RSA PRIVATE KEY-----\nMIIB...\n", "id_rsa");
    test::eq(f.len(), 1);
    test::eq(f[0].label, "Private key block");
    test::eq(f[0].line_no, (usz)1);
}

fn void test_scan_content_password_assignment_value_starting_with_s() @test
{
    // Regression test for a real C3 0.8.3 regex engine bug (see the
    // comment on PATTERNS in security.c3): a \s-derived class earlier in
    // a pattern combined with a literal lowercase 's' used to make any
    // value starting with s/S silently fail to match.
    List{Finding} f = scan_content("PASSWORD=secret\n", "x.env");
    test::eq(f.len(), 1);
}

fn void test_scan_content_password_assignment() @test
{
    List{Finding} f = scan_content("PASSWORD=hunter2\n", "x.env");
    test::eq(f.len(), 1);
    test::eq(f[0].label, "Password assignment");
}

fn void test_scan_content_case_insensitive() @test
{
    List{Finding} f = scan_content("password = \"hunter2\"\n", "x.env");
    test::eq(f.len(), 1);
}

fn void test_scan_content_token_and_api_key() @test
{
    List{Finding} f = scan_content("TOKEN=abc123\nAPI_KEY=xyz789\n", "x.env");
    test::eq(f.len(), 2);
}

fn void test_scan_content_github_token() @test
{
    List{Finding} f = scan_content("ghp_1234567890abcdefghijklmnop\n", "x");
    test::eq(f.len(), 1);
    test::eq(f[0].label, "GitHub token");
}

fn void test_scan_content_aws_key() @test
{
    List{Finding} f = scan_content("AKIAABCDEFGHIJKLMNOP\n", "x");
    test::eq(f.len(), 1);
    test::eq(f[0].label, "AWS access key ID");
}

fn void test_scan_content_authorization_header() @test
{
    List{Finding} f = scan_content("Authorization: Bearer sometoken\n", "x");
    test::eq(f.len(), 1);
}

fn void test_scan_content_word_boundary_avoids_false_positive() @test
{
    // "mypassword_field=x" — PASSWORD isn't preceded by a word boundary
    // here, so this must NOT match (mirrors lib/security.sh's \b usage).
    List{Finding} f = scan_content("mypassword_field=x\n", "x");
    test::eq(f.len(), 0);
}

fn void test_scan_content_line_numbers_correct() @test
{
    String content = "line one\nline two\nPASSWORD=secret\nline four\n";
    List{Finding} f = scan_content(content, "x");
    test::eq(f.len(), 1);
    test::eq(f[0].line_no, (usz)3);
}

fn void test_scan_content_never_carries_matched_text() @test
{
    // The whole point of the scanner: a Finding names the pattern/file/
    // line, never the matched substring. Nothing to assert on the struct
    // shape itself (it has no field for it) — this test exists as a
    // marker so the invariant stays visible if Finding ever grows a field.
    List{Finding} f = scan_content("PASSWORD=hunter2\n", "x");
    test::eq(f.len(), 1);
    test::eq(f[0].label, "Password assignment");
    test::eq(f[0].file, "x");
}

fn void test_scan_file_missing_is_empty_not_error() @test
{
    List{Finding} f = scan_file("test/fixtures/does-not-exist.txt");
    test::eq(f.len(), 0);
}

fn void test_scan_file_directory_is_empty_not_error() @test
{
    List{Finding} f = scan_file("test/fixtures/sample_config");
    test::eq(f.len(), 0);
}

fn void test_scan_paths_aggregates_across_files() @test
{
    List{Finding} f = scan_paths({
        "test/fixtures/sample_config/modules/shell/module.mcm",
        "test/fixtures/does-not-exist.txt",
    });
    test::eq(f.len(), 0); // neither fixture file contains anything secret-shaped
}
