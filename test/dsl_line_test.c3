module machine_config_manager::dsl;
import std::io;
import std::collections::list;

fn void test_lex_empty() @test
{
    List{Line} lines = lex("");
    test::eq(lines.len(), 0);
}

fn void test_lex_comments_and_blanks_dropped() @test
{
    String src = "# a comment\n\nID shell\n   \n# another\nNAME Shell\n";
    List{Line} lines = lex(src);
    test::eq(lines.len(), 2);
    test::eq(lines[0].keyword, "ID");
    test::eq(lines[0].rest, "shell");
    test::eq(lines[1].keyword, "NAME");
    test::eq(lines[1].rest, "Shell");
}

fn void test_lex_line_numbers_survive_dropped_lines() @test
{
    // Line numbers count every physical line, including comments/blanks —
    // so error messages built from them point at the real file line.
    String src = "# comment\n\nID shell\n";
    List{Line} lines = lex(src);
    test::eq(lines.len(), 1);
    test::eq(lines[0].line_no, (usz)3);
}

fn void test_lex_bare_keyword_has_empty_rest() @test
{
    List{Line} lines = lex("HIDDEN\n");
    test::eq(lines.len(), 1);
    test::eq(lines[0].keyword, "HIDDEN");
    test::eq(lines[0].rest, "");
}

fn void test_lex_multiple_spaces_collapsed_into_rest() @test
{
    // Only the split between keyword and rest matters here; push_words
    // (tested separately) is what later collapses runs of spaces within
    // rest itself.
    List{Line} lines = lex("SUPPORTS   arch  ubuntu\n");
    test::eq(lines.len(), 1);
    test::eq(lines[0].keyword, "SUPPORTS");
    test::eq(lines[0].rest, "arch  ubuntu");
}

fn void test_lex_trims_leading_and_trailing_whitespace() @test
{
    List{Line} lines = lex("   ID shell   \n");
    test::eq(lines.len(), 1);
    test::eq(lines[0].keyword, "ID");
    test::eq(lines[0].rest, "shell");
}

fn void test_lex_no_trailing_newline() @test
{
    List{Line} lines = lex("ID shell");
    test::eq(lines.len(), 1);
    test::eq(lines[0].keyword, "ID");
    test::eq(lines[0].rest, "shell");
}

fn void test_lex_comment_must_be_first_char() @test
{
    // '#' only starts a comment as the line's first non-whitespace
    // character — this is deliberately not "strip anything after #",
    // since a value could legitimately contain one (unlikely today, but
    // the lexer shouldn't quietly mangle it).
    List{Line} lines = lex("DESCRIPTION issue #42 support\n");
    test::eq(lines.len(), 1);
    test::eq(lines[0].rest, "issue #42 support");
}

fn void test_push_words_basic() @test
{
    List{String} target;
    target.tinit();
    push_words(&target, "arch ubuntu debian");
    test::eq(target.len(), 3);
    test::eq(target[0], "arch");
    test::eq(target[1], "ubuntu");
    test::eq(target[2], "debian");
}

fn void test_push_words_collapses_extra_spaces() @test
{
    List{String} target;
    target.tinit();
    push_words(&target, "arch    ubuntu");
    test::eq(target.len(), 2);
}

fn void test_push_words_empty_rest_is_noop() @test
{
    List{String} target;
    target.tinit();
    push_words(&target, "");
    test::eq(target.len(), 0);
}

fn void test_push_words_appends_to_existing() @test
{
    // push_words is used for repeatable keywords that may appear on
    // several lines (e.g. two SUPPORTS lines) — it must accumulate, not
    // overwrite.
    List{String} target;
    target.tinit();
    push_words(&target, "arch");
    push_words(&target, "ubuntu debian");
    test::eq(target.len(), 3);
}

fn void test_is_valid_id() @test
{
    test::eq(is_valid_id("shell"), true);
    test::eq(is_valid_id("dev-tools"), true);
    test::eq(is_valid_id("vs_code2"), true);
    test::eq(is_valid_id(""), false);
    test::eq(is_valid_id("Shell"), false);
    test::eq(is_valid_id("2fast"), false);
    test::eq(is_valid_id("has space"), false);
    test::eq(is_valid_id("has.dot"), false);
}
