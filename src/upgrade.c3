module machine_config_manager::upgrade;
import std::io;
import std::collections::list;

<*
 Pure helpers for `mcm upgrade` — fetching/writing/confirming live in
 main.c3's cmd_upgrade, everything here just operates on already-read
 strings so it's unit-testable without touching the network or disk.

 install.sh/config are authored in machine-config's template/, not
 published as machine-config-manager release assets — manager.lock's
 version/checksums are the one thing that's actually tied to a specific
 machine-config-manager release. So "the manager source" this plan
 originally imagined as one URL is really two independently-versioned
 things in practice: MANAGER_SOURCE (machine-config-manager, for the
 binary + manager.lock's checksums) and TEMPLATE_SOURCE (machine-config's
 template/, for install.sh/config's actual bootstrap logic). Both default
 sensibly; --manager-source/--template-source override either
 independently for a fork of either repo.
*>
const String DEFAULT_MANAGER_SOURCE = "https://github.com/p-victor/machine-config-manager";
const String DEFAULT_TEMPLATE_SOURCE = "https://raw.githubusercontent.com/p-victor/machine-config/main/template";

const String CONFIG_REPO_URL_PLACEHOLDER = "__MC_CONFIG_REPO_URL__";

faultdef NOT_YET_CONFIGURED;

<*
 Pulls the already-configured MC_CONFIG_REPO_DEFAULT_URL value out of an
 install.sh's content — the one line `config init` (or a previous
 `upgrade`) wrote. NOT_YET_CONFIGURED if it's still the placeholder (a
 template that was never `config init`-ed) or the line isn't found at all.
*>
fn String? extract_configured_repo_url(String install_sh_content)
{
    String needle = "MC_CONFIG_REPO_DEFAULT_URL=\"";
    foreach (line : install_sh_content.tsplit("\n"))
    {
        String trimmed = line.trim();
        if (!trimmed.starts_with(needle)) continue;
        String rest = trimmed[needle.len..];
        sz? close_quote = rest.index_of_char('"');
        if (catch close_quote) continue;
        String url = rest[0..close_quote - 1];
        if (url == CONFIG_REPO_URL_PLACEHOLDER || url.len == 0) return NOT_YET_CONFIGURED~;
        return url;
    }
    return NOT_YET_CONFIGURED~;
}

<* Replaces install.sh's placeholder with `url` — same substitution config init does. *>
fn String apply_configured_repo_url(String install_sh_content, String url)
{
    return install_sh_content.replace(tmem, CONFIG_REPO_URL_PLACEHOLDER, url);
}

<*
 Lines present in `old_content` but not `new_content` ("removed") and vice
 versa ("added") — a line-set diff, not a true positional/unified diff (no
 diff algorithm here, no new dependency on the `diff` binary either): good
 enough to show *what* changed in a small, mostly-stable bootstrap script
 for a "does this look right" review before overwriting, not a claim of
 minimal edit distance.
*>
struct LineDiff
{
    List{String} removed;
    List{String} added;
}

fn LineDiff line_diff(String old_content, String new_content)
{
    List{String} old_lines;
    old_lines.tinit();
    old_lines.push_all(old_content.tsplit("\n"));
    List{String} new_lines;
    new_lines.tinit();
    new_lines.push_all(new_content.tsplit("\n"));

    LineDiff result;
    result.removed.tinit();
    result.added.tinit();

    foreach (l : old_lines)
    {
        if (!new_lines.contains(l)) result.removed.push(l);
    }
    foreach (l : new_lines)
    {
        if (!old_lines.contains(l)) result.added.push(l);
    }
    return result;
}

fn bool line_diff_is_empty(LineDiff* d) => d.removed.len() == 0 && d.added.len() == 0;

<* Pulls MANAGER_RELEASE="..." out of a manager.lock's content, for the old-\>new version report. *>
fn String? extract_manager_release(String manager_lock_content)
{
    String needle = "MANAGER_RELEASE=\"";
    foreach (line : manager_lock_content.tsplit("\n"))
    {
        String trimmed = line.trim();
        if (!trimmed.starts_with(needle)) continue;
        String rest = trimmed[needle.len..];
        sz? close_quote = rest.index_of_char('"');
        if (catch close_quote) continue;
        return rest[0..close_quote - 1];
    }
    return NOT_YET_CONFIGURED~;
}
