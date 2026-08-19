module machine_config_manager;
import machine_config_manager::discover;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import machine_config_manager::platform;
import machine_config_manager::git;
import machine_config_manager::security;
import machine_config_manager::prompt;
import std::io;
import std::io::path;
import std::os::env;
import std::collections::list;
import std::collections::map;

const String MANAGER_VERSION = "0.1.0";

alias StringListMap = HashMap{String, List{String}};

fn int main(String[] args)
{
    if (args.len < 2)
    {
        io::printn("Usage: machine-config-manager <command> [args]");
        io::printn("Commands:");
        io::printn("  validate [--config-root PATH]");
        io::printn("  status   [--config-root PATH]");
        io::printn("  diff     [--config-root PATH]");
        io::printn("  publish  [--config-root PATH] [--message MSG] [--yes] [--allow-secrets]");
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
        case "publish":
            return cmd_publish(args[2..]);
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

<*
 Groups changed paths by owning module (first path segment after
 "modules/", else "(other)") and prints them indented — same shape as
 commands/publish.sh's mc_publish_group_by_module.
*>
fn void print_changed_by_module(String[] files)
{
    List{String} module_order;
    module_order.tinit();
    StringListMap by_module;
    by_module.tinit();

    foreach (f : files)
    {
        String mod = "(other)";
        if (f.starts_with("modules/"))
        {
            String rest = f[8..];
            sz? slash = rest.index_of_char('/');
            if (try s = slash) mod = rest[0..s - 1];
        }
        if (!by_module.has_key(mod))
        {
            module_order.push(mod);
            List{String} fresh;
            fresh.tinit();
            by_module.set(mod, fresh);
        }
        List{String}* bucket = by_module.get_ref(mod)!!;
        bucket.push(f);
    }

    foreach (m : module_order)
    {
        io::printfn("  %s:", m);
        List{String}* bucket = by_module.get_ref(m)!!;
        foreach (f : bucket.to_tarray())
        {
            io::printfn("    %s", f);
        }
    }
}

fn int cmd_publish(String[] args)
{
    String config_root = extract_config_root(args);
    String message = "";
    bool assume_yes = false;
    bool allow_secrets = false;
    for (usz i = 0; i < args.len; i++)
    {
        switch (args[i])
        {
            case "--message":
                if (i + 1 < args.len) { message = args[i + 1]; i++; }
            case "--yes":
                assume_yes = true;
            case "--allow-secrets":
                allow_secrets = true;
            default:
                break;
        }
    }

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
        io::printn("git is not installed — publish needs it. Install git to use this command.");
        return 1;
    }
    if (!git::is_repo(config_root))
    {
        io::printfn("Not a git repository: %s", config_root);
        return 65;
    }

    io::printfn("Publish");
    io::printn("");
    io::printfn("Config root: %s", config_root);
    io::printn("");

    String porcelain = git::status_porcelain(config_root) ?? "";
    List{String} changed = git::parse_changed_files(porcelain);

    if (changed.len() == 0)
    {
        io::printn("Nothing to publish (working tree clean).");
        io::printn("");
        return sync_with_remote(config_root);
    }

    io::printn("Changes by module");
    print_changed_by_module(changed.to_tarray());
    io::printn("");

    io::printn("Secret scan");
    List{String} scan_targets;
    scan_targets.tinit();
    foreach (f : changed)
    {
        scan_targets.push(string::tformat("%s/%s", config_root, f));
    }
    List{security::Finding} findings = security::scan_paths(scan_targets.to_tarray());
    if (findings.len() == 0)
    {
        io::printn("  No likely secrets found.");
    }
    else
    {
        io::printn("  Possible secrets found (this scan is best-effort, not comprehensive):");
        foreach (fnd : findings)
        {
            String rel = fnd.file.strip_prefix(string::tformat("%s/", config_root));
            io::printfn("    %s — %s:%d", fnd.label, rel, fnd.line_no);
        }
        if (!allow_secrets)
        {
            io::printn("");
            io::printn("Refusing to publish: review the findings above, then re-run with --allow-secrets once you've confirmed none of them are real.");
            return 1;
        }
        io::printn("  Publishing anyway (--allow-secrets).");
    }
    io::printn("");

    io::printn("Validate");
    int validate_status = cmd_validate({ "--config-root", config_root });
    io::printn("");
    if (validate_status != 0)
    {
        io::printn("Refusing to publish until validation passes (see output above).");
        return 65;
    }

    if (message.len == 0)
    {
        String? entered = prompt::input("Commit message");
        if (catch entered)
        {
            io::printn("Failed to read a commit message.");
            return 2;
        }
        message = entered;
    }
    if (message.len == 0)
    {
        io::printn("Commit message must not be empty.");
        return 64;
    }

    if (!assume_yes && !prompt::confirm("Commit these changes?", false))
    {
        io::printn("Aborted.");
        return 1;
    }

    if (catch git::add_all(config_root))
    {
        io::printn("git add failed; see output above.");
        return 1;
    }
    if (catch git::commit(config_root, message))
    {
        io::printn("git commit failed; see output above.");
        return 1;
    }
    io::printn("Committed.");
    io::printn("");

    int sync_status = sync_with_remote(config_root);
    if (sync_status != 0) return sync_status;
    io::printn("");

    if (!git::has_remote(config_root))
    {
        io::printn("Committed locally (no git remote configured; nothing to push).");
        return 0;
    }

    if (!assume_yes && !prompt::confirm("Push to the remote?", false))
    {
        io::printfn("Not pushed. Push manually when ready: git -C \"%s\" push", config_root);
        return 0;
    }
    if (catch git::push(config_root))
    {
        io::printn("git push failed; see output above.");
        return 1;
    }
    io::printn("Published.");
    return 0;
}

<*
 Fetch, then fast-forward only — never auto-resolves. No-ops if no remote
 is configured. Shared by the "nothing to publish, but might still be
 behind" early return and the post-commit sync.
*>
fn int sync_with_remote(String config_root)
{
    if (!git::has_remote(config_root))
    {
        io::printn("No git remote configured; skipping fetch/pull.");
        return 0;
    }
    io::printn("Syncing with remote");
    if (catch git::fetch(config_root))
    {
        io::printn("git fetch failed; see output above.");
        return 1;
    }
    if (catch git::merge_ff_only(config_root))
    {
        io::printn("Could not fast-forward from the remote (local and remote have diverged) — resolve manually; never auto-resolving conflicts.");
        return 1;
    }
    io::printn("Up to date with remote.");
    return 0;
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
