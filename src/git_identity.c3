module machine_config_manager::git_identity;
import std::io;
import std::io::file;
import std::io::path;

<*
 The machine-local Git identity include: the personal config repo tracks
 a .gitconfig (via a module's LINK, e.g. a git module) containing
 `[include]\n    path = ~/.config/git/local.inc`. This is what manages
 that include target — a small, untracked, machine-local file holding
 [user] name/email, written from GIT_NAME/GIT_EMAIL once those local
 values are set. Nothing here touches the user's tracked .gitconfig
 directly — the include directive living there is a declared fact of the
 personal repo, same trust class as any other dotfile. Same role as
 lib/git.sh.
*>
enum Status
{
    CREATED,
    UPDATED,
    UNCHANGED,
}

fn String render_identity(String name, String email) => string::tformat("[user]\n    name = %s\n    email = %s\n", name, email);

fn bool identity_matches(String name, String email, String file_path)
{
    char[]? raw = file::load_temp(file_path);
    if (catch raw) return false;
    return (String)raw == render_identity(name, email);
}

fn void? write_identity(String name, String email, String file_path)
{
    String? dir = file_path.path_tdirname();
    if (try d = dir) (void)path::mkdir(d, true);
    file::save(file_path, render_identity(name, email))!;
}

<*
 Writes/refreshes local.inc if it doesn't already hold exactly this name/
 email. Reports created/updated/unchanged, matching symlink.c3's
 vocabulary. Callers reading GIT_NAME/GIT_EMAIL from local values decide
 what to do when either is unset — this function only writes when both
 are given (never forced globally, same as env_require_local_value's
 opt-in-per-environment model).
*>
fn Status? ensure_identity(String name, String email, String file_path)
{
    if (identity_matches(name, email, file_path)) return UNCHANGED;
    bool existed = path::exists(path::tnew(file_path) ?? (Path)"");
    write_identity(name, email, file_path)!;
    return existed ? UPDATED : CREATED;
}

fn bool identity_has_name(String file_path)
{
    char[]? raw = file::load_temp(file_path);
    if (catch raw) return false;
    foreach (line : ((String)raw).tsplit("\n"))
    {
        String t = line.trim();
        if (t.starts_with("name") && t.len > 4 && t[4] == ' ')
        {
            sz? eq = t.index_of_char('=');
            if (try e = eq)
            {
                if (t[e + 1..].trim().len > 0) return true;
            }
        }
    }
    return false;
}

fn bool identity_has_email(String file_path)
{
    char[]? raw = file::load_temp(file_path);
    if (catch raw) return false;
    foreach (line : ((String)raw).tsplit("\n"))
    {
        String t = line.trim();
        if (t.starts_with("email") && t.len > 5 && t[5] == ' ')
        {
            sz? eq = t.index_of_char('=');
            if (try e = eq)
            {
                if (t[e + 1..].trim().len > 0) return true;
            }
        }
    }
    return false;
}
