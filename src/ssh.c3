module machine_config_manager::ssh;
import machine_config_manager::prompt;
import std::io;
import std::io::file;
import std::io::path;
import std::os::process;
import std::os::env;

<*
 SSH key detection/generation. Never stores or prints a private key —
 every function here either checks for a key's *existence* or reads its
 *.pub counterpart. Same role as lib/ssh.sh.
*>
const String[3] KEY_TYPES = { "id_ed25519", "id_ecdsa", "id_rsa" };

fn String default_ssh_dir()
{
    String? home = env::tget_var("HOME");
    if (try h = home) return string::tformat("%s/.ssh", h);
    return "./.ssh";
}

<* First existing private key (paired with a .pub) among the common types, or none. *>
fn String? find_existing_key(String ssh_dir)
{
    foreach (t : KEY_TYPES)
    {
        String priv = string::tformat("%s/%s", ssh_dir, t);
        String pub = string::tformat("%s.pub", priv);
        if (path::is_file(path::tnew(priv) ?? (Path)"") && path::is_file(path::tnew(pub) ?? (Path)""))
        {
            return priv;
        }
    }
    return NO_KEY_FOUND~;
}

faultdef NO_KEY_FOUND;

fn String public_key_path(String private_key_path) => string::tformat("%s.pub", private_key_path);

<* The public key's contents only. *>
fn String? show_public_key(String private_key_path)
{
    String pub = public_key_path(private_key_path);
    char[] raw = file::load_temp(pub)!;
    return (String)raw;
}

<*
 Generates a new Ed25519 key at `path`. Asks before overwriting an
 existing file (via prompt::confirm — defaults to declining). Passphrase
 prompting is ssh-keygen's own /dev/tty behavior, untouched here. Mutates
 the real filesystem — safe to test against a scratch path (unlike
 package installs, this never touches system state or needs a privilege
 escalation), just never against a real ~/.ssh in an automated test.
*>
faultdef GENERATION_DECLINED;

fn void? generate_key(String path, String comment)
{
    if (path::exists(path::tnew(path) ?? (Path)""))
    {
        if (!prompt::confirm(string::tformat("A key already exists at %s. Overwrite it?", path), false))
        {
            return GENERATION_DECLINED~;
        }
    }
    String? dir = path.path_tdirname();
    if (try d = dir)
    {
        (void)path::mkdir(d, true);
        (void)process::run({ "chmod", "700", d });
    }
    process::run({ "ssh-keygen", "-t", "ed25519", "-C", comment, "-f", path }, process::SpawnOptions.INHERIT_STDIO)!;
}

<*
 True if GitHub recognizes the loaded key. GitHub's SSH endpoint always
 exits non-zero on this probe (it refuses a shell by design) — success is
 read from the output text, not the exit status.
*>
fn bool test_github_auth()
{
    char[4096] buf;
    String? out = process::run_capture_stdout(&buf, {
        "ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=5", "-T", "git@github.com"
    }, process::SpawnOptions.STDERR_TO_STDOUT);
    if (catch out) return false;
    return out.contains("successfully authenticated");
}

<*
 Offers to generate a new key if none is found under the common names.
 No-ops entirely under `non_interactive` or without a controlling
 terminal, so an automated install never generates a credential without
 a human present. An existing key under a standard name is treated as
 "use existing" automatically — no extra prompt needed when one's already
 found. Same behavior as lib/ssh.sh's mc_ssh_ensure_key_interactive,
 simplified to a plain y/n instead of a two-item menu (this DSL/CLI's
 prompt surface only has confirm()/input(), not a general menu prompt —
 env_select.c3's numbered menu is a different shape built for a longer,
 open-ended list of environments, not a fixed two-choice generate-or-skip).
*>
fn void ensure_key_interactive(String ssh_dir, String comment, bool non_interactive)
{
    if (non_interactive || !io::stdin().isatty()) return;

    String? existing = find_existing_key(ssh_dir);
    if (try e = existing)
    {
        io::printfn("SSH key found: %s", e);
        return;
    }

    if (!prompt::confirm("No SSH key found. Generate a new Ed25519 key?", true))
    {
        io::printn("Skipped SSH key setup.");
        return;
    }

    String path = string::tformat("%s/id_ed25519", ssh_dir);
    if (catch generate_key(path, comment))
    {
        io::printn("SSH key generation skipped.");
        return;
    }
    io::printfn("SSH key generated: %s", path);
    io::printn("");
    io::printn("Public key:");
    if (try pub = show_public_key(path))
    {
        io::printn(pub);
    }
    io::printn("");
    io::printn("Add it to GitHub at: https://github.com/settings/keys");
}
