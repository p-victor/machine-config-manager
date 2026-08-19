module machine_config_manager::dsl;
import std::collections::list;

<*
 One non-blank, non-comment line of a .mcm file, already split into its
 leading keyword and the (trimmed) remainder. Comments ('#' as the first
 non-whitespace character) and blank lines never produce a Line at all —
 the parser only ever sees DSL statements.
*>
struct Line
{
    String keyword;
    String rest;
    usz line_no;
}

<*
 Tokenizes .mcm source into Lines. Deliberately dumb: doesn't know about
 any keyword's semantics (how many args it takes, whether it's a bare
 flag) — that's the parser's job per file kind (module vs. environment).
*>
fn List{Line} lex(String source)
{
    List{Line} lines;
    lines.tinit();
    String[] raw_lines = source.tsplit("\n");
    foreach (i, raw : raw_lines)
    {
        String trimmed = raw.trim();
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;

        String keyword;
        String rest;
        sz? sp = trimmed.index_of_char(' ');
        if (catch sp)
        {
            keyword = trimmed;
            rest = "";
        }
        else
        {
            keyword = trimmed[0..sp - 1];
            rest = trimmed[sp + 1..].trim();
        }
        lines.push({ keyword, rest, (usz)(i + 1) });
    }
    return lines;
}

<*
 Splits a line's `rest` on whitespace into individual words, ignoring any
 run of extra spaces between them. Used by every repeatable simple field
 (SUPPORTS, REQUIRES, EXTENDS, ENABLE, ...) so `SUPPORTS arch ubuntu debian`
 parses as three values from one line.
*>
fn void push_words(List{String}* target, String rest)
{
    if (rest.len == 0) return;
    String[] words = rest.tsplit(" ", skip_empty: true);
    foreach (w : words)
    {
        if (w.len > 0) target.push(w);
    }
}

<*
 Module/environment ids must match ^[a-z][a-z0-9_-]*$ — same pattern the
 Bash implementation enforces (MC_ID_PATTERN in lib/core.sh).
*>
fn bool is_valid_id(String s)
{
    if (s.len == 0) return false;
    char c0 = s[0];
    if (c0 < 'a' || c0 > 'z') return false;
    foreach (c : s)
    {
        bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok) return false;
    }
    return true;
}
