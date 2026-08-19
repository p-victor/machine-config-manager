module machine_config_manager::security;
import std::encoding::experimental::regex;
import std::io;
import std::io::file;
import std::io::path;
import std::collections::list;

<*
 Conservative, best-effort secret scanner for `publish` — same patterns
 and same philosophy as lib/security.sh: not comprehensive (genuinely
 private material like SSH keys/local.env lives outside the repo entirely
 by this project's own design; this only catches secret-*shaped content*
 that ends up somewhere unexpected). A finding never carries the matched
 text — only which pattern matched, which file, and which line — since
 the match could well be the secret value itself.
*>
struct PatternDef
{
    String label;
    String pattern;
}

// `[ \t]` everywhere the natural pattern would be `\s`/`\S`: C3 0.8.3's
// std::encoding::experimental::regex has a real bug where a `\s`-derived
// character class combined with a literal lowercase 's' elsewhere in the
// same pattern silently fails to match strings starting with 's'/'S'
// (verified directly — `password=secret`/`PASSWORD=S` never matched,
// `password=x` did; switching `\s`/`\S` to an explicit `[ \t]`/`[^ \t]`
// class fixed it with identical behavior otherwise). Confirmed against
// the module's own name ("experimental") — do not "simplify" this back
// to `\s` without re-verifying the bug is actually fixed upstream first,
// or every one of these patterns silently stops catching secrets that
// happen to start with s/S.
const PatternDef[] PATTERNS = {
    { "Private key block", `-----BEGIN[A-Z ]*PRIVATE KEY-----` },
    { "Password assignment", `\bPASSWORD[ \t]*=[ \t]*['"]?[^ \t'"]` },
    { "Token assignment", `\bTOKEN[ \t]*=[ \t]*['"]?[^ \t'"]` },
    { "API key assignment", `\bAPI_KEY[ \t]*=[ \t]*['"]?[^ \t'"]` },
    { "Secret assignment", `\bSECRET[ \t]*=[ \t]*['"]?[^ \t'"]` },
    { "Authorization header", `Authorization:[ \t]*(Bearer|Basic)[ \t]+[^ \t]` },
    { "GitHub token", `gh[pousr]_[A-Za-z0-9]{20,}` },
    { "AWS access key ID", `AKIA[0-9A-Z]{16}` },
};

struct Finding
{
    String label;
    String file;
    usz line_no;
}

<*
 Scans `content` (already-read file text) line by line against every
 pattern, case-insensitively — `file_label` is just carried through into
 each Finding for reporting, this function never touches the filesystem.
*>
fn List{Finding} scan_content(String content, String file_label)
{
    List{Finding} findings;
    findings.tinit();
    String[] lines = content.tsplit("\n");
    foreach (p : PATTERNS)
    {
        regex::Regex? re = regex::compile(tmem, p.pattern, regex::CompileFlags.EXTENDED | regex::CompileFlags.ICASE);
        if (catch re) continue;
        foreach (i, line : lines)
        {
            if (re.matches(line))
            {
                findings.push({ p.label, file_label, (usz)(i + 1) });
            }
        }
    }
    return findings;
}

<*
 Scans one file on disk. A missing/unreadable path is nothing to scan
 (empty result), not an error — matches lib/security.sh's
 mc_security_scan_file, which treats "not a regular file" the same way
 (a path from `git status` may already be deleted by the time this runs).
*>
fn List{Finding} scan_file(String file_path)
{
    List{Finding} empty;
    empty.tinit();

    Path? p = path::tnew(file_path);
    if (catch p) return empty;
    if (!path::is_file(p)) return empty;

    char[]? raw = file::load_temp(file_path);
    if (catch raw) return empty;

    return scan_content((String)raw, file_path);
}

<*
 Scans every given path, silently skipping anything that isn't a regular
 file. Every finding across every path, in path order.
*>
fn List{Finding} scan_paths(String[] paths)
{
    List{Finding} all;
    all.tinit();
    foreach (p : paths)
    {
        all.push_all(scan_file(p).to_tarray());
    }
    return all;
}
