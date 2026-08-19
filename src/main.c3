module machine_config_manager;
import machine_config_manager::discover;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import machine_config_manager::platform;
import machine_config_manager::git;
import std::io;
import std::io::path;
import std::os::env;
import std::collections::list;

const String MANAGER_VERSION = "0.1.0";

fn int main(String[] args)
{
    if (args.len < 2)
    {
        io::printn("Usage: machine-config-manager <command> [args]");
        io::printn("Commands:");
        io::printn("  validate [--config-root PATH]");
        io::printn("  status   [--config-root PATH]");
        io::printn("  diff     [--config-root PATH]");
        return 64;
    }

    switch (args[1])
    {
        case "validate":
            return cmd_validate(args[2..]);
        case "status":
            return cmd_status(args[2..]);
        case "diff":
            return cmd_diff(args[2..]);
        default:
            io::printfn("Unknown command: %s", args[1]);
            return 64;
    }
}

<*
 Default personal-config-repo location: $XDG_DATA_HOME/machine-config/repo,
 falling back to $HOME/.local/share/machine-config/repo — same default
 lib/xdg.sh's mc_config_repo_root resolves to.
*>
fn String default_config_root()
{
    String? xdg_data = env::tget_var("XDG_DATA_HOME");
    if (try base = xdg_data)
    {
        return string::tformat("%s/machine-config/repo", base);
    }
    String? home = env::tget_var("HOME");
    if (try h = home)
    {
        return string::tformat("%s/.local/share/machine-config/repo", h);
    }
    return "./machine-config/repo";
}

fn String extract_config_root(String[] args)
{
    String config_root = default_config_root();
    for (usz i = 0; i < args.len; i++)
    {
        if (args[i] == "--config-root" && i + 1 < args.len)
        {
            config_root = args[i + 1];
            i++;
        }
    }
    return config_root;
}

fn int cmd_status(String[] args)
{
    String config_root = extract_config_root(args);

    platform::Platform? p = platform::detect();
    if (catch err = p)
    {
        io::printfn("Failed to detect platform: %s", err);
        return 1;
    }

    io::printn("Machine configuration");
    io::printn("");

    io::printn("Platform");
    io::printfn("  Distribution: %s", p.pretty_name);
    String context_label = "Native";
    if (p.is_wsl) context_label = string::tformat("WSL%d", p.wsl_version);
    io::printfn("  Environment:  %s", context_label);
    io::printfn("  Architecture: %s", p.arch);
    io::printfn("  User:         %s", p.username);
    io::printn("");

    io::printn("Manager");
    io::printfn("  Version: %s", MANAGER_VERSION);
    io::printn("");

    io::printn("Repository");
    Path? root_path = path::tnew(config_root);
    if (catch root_path)
    {
        io::printfn("  Not found (%s)", config_root);
        return 0;
    }
    if (!path::is_dir(root_path))
    {
        io::printfn("  Not found (%s)", config_root);
        return 0;
    }
    io::printfn("  Path: %s", config_root);

    if (git::is_available() && git::is_repo(config_root))
    {
        String? branch = git::current_branch(config_root);
        String branch_label = "(detached)";
        if (try b = branch)
        {
            if (b.len > 0) branch_label = b;
        }
        io::printfn("  Branch: %s", branch_label);

        int? count = git::uncommitted_count(config_root);
        if (try c = count)
        {
            if (c == 0)
            {
                io::printn("  No uncommitted changes");
            }
            else
            {
                io::printfn("  %d uncommitted change(s)", c);
            }
        }
    }
    else
    {
        io::printn("  Not a git repository");
    }

    return 0;
}

fn int cmd_diff(String[] args)
{
    String config_root = extract_config_root(args);

    Path? root_path = path::tnew(config_root);
    if (catch root_path)
    {
        io::printfn("Config root not found: %s", config_root);
        return 66;
    }
    if (!path::is_dir(root_path))
    {
        io::printfn("Config root not found: %s", config_root);
        return 66;
    }

    if (!git::is_available())
    {
        io::printn("git is not installed — nothing to diff. Install git to use this command.");
        return 1;
    }
    if (!git::is_repo(config_root))
    {
        io::printfn("Not a git repository: %s", config_root);
        return 65;
    }

    int? status = git::diff(config_root);
    if (catch err = status)
    {
        io::printfn("git diff failed: %s", err);
        return 1;
    }
    return status;
}

fn int cmd_validate(String[] args)
{
    String config_root = extract_config_root(args);

    discover::ModuleDiscovery md = discover::discover_modules(config_root);
    discover::EnvironmentDiscovery ed = discover::discover_environments(config_root);

    List{String} errors;
    errors.tinit();
    errors.push_all(md.errors.to_tarray());
    errors.push_all(ed.errors.to_tarray());
    errors.push_all(registry::validate_from_chains(&md.modules).to_tarray());
    errors.push_all(registry::validate_extends_refs(&ed.environments).to_tarray());
    errors.push_all(registry::validate_enable_refs(&ed.environments, &md.modules).to_tarray());

    // Per-environment: resolve the full module set (EXTENDS, then
    // REQUIRES on top), then check EXCLUDES/LINK conflicts within it.
    // resolve_extends_modules's own errors (dangling EXTENDS refs,
    // EXTENDS cycles) get folded in here too — validate_extends_refs
    // above only catches the dangling-ref half, not cycles, which only
    // surface while actually walking a chain.
    foreach (&e : ed.environments.environments)
    {
        List{String} ext_errors;
        ext_errors.tinit();
        List{String} enabled = registry::resolve_extends_modules(&ed.environments, e.id, &ext_errors);
        foreach (err : ext_errors)
        {
            errors.push(string::tformat("environment \"%s\": %s", e.id, err));
        }

        List{String} req_errors;
        req_errors.tinit();
        List{String} resolved = registry::expand_requires(&md.modules, enabled.to_tarray(), &req_errors);
        foreach (err : req_errors)
        {
            errors.push(string::tformat("environment \"%s\": %s", e.id, err));
        }

        List{registry::ConflictPair} conflicts = registry::find_conflicts(&md.modules, resolved.to_tarray());
        foreach (c : conflicts)
        {
            errors.push(string::tformat("environment \"%s\": conflicting modules both enabled: \"%s\", \"%s\"", e.id, c.a, c.b));
        }

        List{registry::LinkConflict} link_conflicts = registry::find_link_conflicts(&md.modules, resolved.to_tarray());
        foreach (lc : link_conflicts)
        {
            errors.push(string::tformat(
                "environment \"%s\": modules \"%s\" (%s) and \"%s\" (%s) both link overlapping paths",
                e.id, lc.module_a, lc.path_a, lc.module_b, lc.path_b));
        }
    }

    io::printfn("Validating %s", config_root);
    io::printfn("  %d module(s), %d environment(s) discovered", md.modules.modules.len(), ed.environments.environments.len());
    io::printn("");

    if (errors.len() == 0)
    {
        io::printn("OK — no problems found.");
        return 0;
    }

    io::printfn("%d problem(s) found:", errors.len());
    foreach (err : errors)
    {
        io::printfn("  - %s", err);
    }
    return 1;
}
