module machine_config_manager::local_values;
import machine_config_manager::dsl;
import machine_config_manager::prompt;
import machine_config_manager::xdg;
import std::io;
import std::io::file;
import std::io::path;
import std::os::process;
import std::collections::list;
import std::collections::map;

<*
 Machine-local, never-committed values an environment needs (GIT_NAME,
 EDITOR, ...) — same role as lib/local_values.sh's local.env, one
 NAME=VALUE per line. Deliberately NOT bash-sourced the way the original
 is: since nothing here ever executes this file as code, there's no need
 for printf '%q' shell-escaping on write or shell-parsing on read — a
 plain NAME=VALUE line is both simpler and safer (a malformed file can't
 do anything beyond being misread, unlike a sourced one).
*>
alias LocalValues = HashMap{String, String};

fn String default_local_env_file() => xdg::local_env_file();

<*
 Parses NAME=VALUE lines (blank lines and #-prefixed comments ignored —
 same convention as every other plain-list file in this project, e.g.
 packages.arch). Malformed lines (no '=') are silently skipped rather
 than erroring: this file is machine-local and not meant to be
 hand-validated the way committed .mcm files are.
*>
fn LocalValues parse(String content)
{
    LocalValues values;
    values.tinit();
    foreach (line : content.tsplit("\n"))
    {
        String trimmed = line.trim();
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;
        sz? eq = trimmed.index_of_char('=');
        if (catch eq) continue;
        String name = trimmed[0..eq - 1];
        String value = trimmed[eq + 1..];
        values.set(name, value);
    }
    return values;
}

fn String format_line(String name, String value) => string::tformat("%s=%s\n", name, value);

<*
 Loads local.env from its default (or given) path. A missing file is
 empty values, not an error — same as lib/local_values.sh's
 mc_local_values_load returning 1 (harmlessly) when the file doesn't
 exist yet.
*>
fn LocalValues load(String file_path)
{
    char[]? raw = file::load_temp(file_path);
    if (catch raw)
    {
        LocalValues empty;
        empty.tinit();
        return empty;
    }
    return parse((String)raw);
}

<*
 Writes every default (DEFAULT_LOCAL) not already present, then prompts
 (via prompt::input — fails clearly under a closed/non-interactive stdin
 rather than hanging) for every required (REQUIRE_LOCAL) value still
 unset after defaults are applied. Creates the file and its parent
 directory if needed, and always leaves it chmod 600 — same flow as
 lib/local_values.sh's mc_local_values_ensure_for_environment, just
 operating on parsed EnvironmentDecl fields instead of the Bash DSL's
 MC_ENV_DEFAULT_LOCAL_VALUES/MC_ENV_REQUIRED_LOCAL_VALUES globals.
*>
fn LocalValues? ensure_for_environment(dsl::EnvironmentDecl* env, String file_path)
{
    String? dir = file_path.path_tdirname();
    if (try d = dir) (void)path::mkdir(d, true);

    LocalValues values = load(file_path);

    foreach (def : env.default_local)
    {
        if (!values.has_key(def.name))
        {
            values.set(def.name, def.value);
        }
    }

    List{String} missing;
    missing.tinit();
    foreach (name : env.require_local)
    {
        if (!values.has_key(name) || values.get(name)!!.len == 0)
        {
            missing.push(name);
        }
    }

    if (missing.len() > 0)
    {
        io::printn("This environment needs a few machine-local values, stored");
        io::printfn("privately in %s (never committed to your config repo).", file_path);
        foreach (name : missing)
        {
            String value = prompt::input(string::tformat("Enter a value for %s", name))!;
            values.set(name, value);
        }
    }

    write(file_path, &values)!;
    return values;
}

fn void? write(String file_path, LocalValues* values)
{
    DString out;
    out.tinit();
    foreach (name : values.tkeys())
    {
        out.append(format_line(name, values.get(name)!!));
    }
    file::save(file_path, out.str_view())!;
    // No chmod binding in std — shells out, same primitive-delegation
    // pattern already used for uname/git rather than hand-rolling a
    // libc extern binding.
    (void)process::run({ "chmod", "600", file_path });
}
