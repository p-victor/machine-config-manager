module machine_config_manager;
import machine_config_manager::discover;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import machine_config_manager::platform;
import machine_config_manager::git;
import machine_config_manager::security;
import machine_config_manager::prompt;
import machine_config_manager::xdg;
import machine_config_manager::package;
import machine_config_manager::package_pacman;
import machine_config_manager::package_apt;
import machine_config_manager::aur;
import machine_config_manager::module_links;
import machine_config_manager::symlink;
import machine_config_manager::env_select;
import machine_config_manager::local_values;
import machine_config_manager::git_identity;
import machine_config_manager::ssh;
import machine_config_manager::manual_tasks;
import std::io;
import std::io::path;
import std::io::file;
import std::os::env;
import std::collections::list;
import std::collections::map;

const String MANAGER_VERSION = "0.1.0";

alias StringListMap = HashMap{String, List{String}};

fn int main(String[] args)
{
    if (args.len < 2)
    {
        io::printn("Usage: mcm <command> [args]");
        io::printn("Commands:");
        io::printn("  validate [--config-root PATH]");
        io::printn("  status   [--config-root PATH]");
        io::printn("  diff     [--config-root PATH]");
        io::printn("  publish  [--config-root PATH] [--message MSG] [--yes] [--allow-secrets]");
        io::printn("  install  [--config-root PATH] [--environment ID] [--dry-run] [--yes] [--non-interactive]");
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
        case "install":
            return cmd_install(args[2..]);
        default:
            io::printfn("Unknown command: %s", args[1]);
            return 64;
    }
}

fn String extract_config_root(String[] args)
{
    String config_root = xdg::config_repo_root();
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

fn String home_dir()
{
    String? h = env::tget_var("HOME");
    if (try v = h) return v;
    return ".";
}

fn String? read_saved_environment()
{
    char[]? raw = file::load_temp(xdg::saved_environment_file());
    if (catch raw) return NO_SAVED_ENVIRONMENT~;
    String v = ((String)raw).trim();
    if (v.len == 0) return NO_SAVED_ENVIRONMENT~;
    return v;
}

faultdef NO_SAVED_ENVIRONMENT;

fn void? save_default_environment(String id)
{
    String f = xdg::saved_environment_file();
    String? dir = f.path_tdirname();
    if (try d = dir) (void)path::mkdir(d, true);
    file::save(f, string::tformat("%s\n", id))!;
}

fn void print_package_list(String label, String[] names)
{
    if (names.len == 0) return;
    io::printfn("  %s: %s", label, string::join(tmem, names, ", "));
}

<*
 Selects the environment to install: --environment > saved default
 (interactively confirmed, or used outright under --non-interactive) >
 the compatible-environments menu. Same precedence as
 commands/install.sh's mc_install_select_environment.
*>
fn String? select_environment(discover::EnvironmentDiscovery* ed, platform::Platform* plat, String env_override, bool non_interactive)
{
    if (env_override.len > 0) return env_override;

    String? saved = read_saved_environment();
    if (try s = saved)
    {
        if (non_interactive) return s;
        if (prompt::confirm(string::tformat("Use saved environment \"%s\"?", s), true)) return s;
    }

    if (non_interactive) return NO_ENVIRONMENT_SELECTED~;

    List{String} ids = env_select::compatible_ids(&ed.environments, plat.distro_id, plat.context, plat.arch);
    if (ids.len() == 0) return NO_ENVIRONMENT_SELECTED~;
    return env_select::select_interactive(&ed.environments, &ids);
}

faultdef NO_ENVIRONMENT_SELECTED;

<*
 install: discover -> select an environment -> resolve its full module
 set -> plan packages (pacman/apt, plus AUR on Arch) -> (--dry-run: show
 the file-deployment plan and stop) -> confirm -> install packages ->
 deploy files -> local values -> Git identity -> SSH (interactive only) ->
 manual tasks checklist -> save the selected environment as the default.
 Mirrors commands/install.sh's cmd_main throughout — see that file for
 the line-by-line mapping. `doctor` is out of scope for this pass, same
 as everywhere else in this project right now.
*>
fn int cmd_install(String[] args)
{
    String config_root = xdg::config_repo_root();
    String env_override = "";
    bool dry_run = false;
    bool assume_yes = false;
    bool non_interactive = false;
    for (usz i = 0; i < args.len; i++)
    {
        switch (args[i])
        {
            case "--config-root":
                if (i + 1 < args.len) { config_root = args[i + 1]; i++; }
            case "--environment":
                if (i + 1 < args.len) { env_override = args[i + 1]; i++; }
            case "--dry-run":
                dry_run = true;
            case "--yes":
                assume_yes = true;
            case "--non-interactive":
                non_interactive = true;
            default:
                break;
        }
    }

    platform::Platform? plat_opt = platform::detect();
    if (catch err = plat_opt)
    {
        io::printfn("Failed to detect platform: %s", err);
        return 3;
    }
    platform::Platform plat = plat_opt;

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
    // Resolved to an absolute path before anything derives a symlink
    // source from it: symlink.c3 always uses its source as-is and
    // expects the caller to have already made it absolute — left
    // relative, every deployed link would point at a path relative to
    // whatever directory happened to be current when install ran.
    Path? abs = config_root.to_absolute_path(tmem);
    if (try a = abs) config_root = (String)a;

    io::printn("Install");
    io::printn("");
    io::printfn("Config root: %s", config_root);
    io::printfn("Platform:    %s / %s / %s", plat.distro_id, plat.context, plat.arch);
    io::printn("");

    discover::ModuleDiscovery md = discover::discover_modules(config_root);
    discover::EnvironmentDiscovery ed = discover::discover_environments(config_root);

    String? selected = select_environment(&ed, &plat, env_override, non_interactive);
    if (catch selected)
    {
        io::printn("No environment specified, no confirmed saved default, and none could be chosen interactively — pass --environment.");
        return 65;
    }
    String env_id = selected;

    dsl::EnvironmentDecl*? env_ptr = ed.environments.find(env_id);
    if (catch env_ptr)
    {
        io::printfn("Unknown environment: %s", env_id);
        return 65;
    }
    if (!env_select::is_compatible(env_ptr, plat.distro_id, plat.context, plat.arch))
    {
        io::printfn("Environment \"%s\" is not compatible with this machine (%s, %s, %s).", env_id, plat.distro_id, plat.context, plat.arch);
        return 65;
    }
    if (env_ptr.deprecated)
    {
        io::printfn("Warning: environment \"%s\" is deprecated.", env_id);
    }

    List{String} ext_errors;
    ext_errors.tinit();
    List{String} enabled = registry::resolve_extends_modules(&ed.environments, env_id, &ext_errors);
    List{String} req_errors;
    req_errors.tinit();
    List{String} resolved = registry::expand_requires(&md.modules, enabled.to_tarray(), &req_errors);
    if (ext_errors.len() > 0 || req_errors.len() > 0)
    {
        io::printn("Failed to resolve this environment's modules; run `mcm validate` for details.");
        return 65;
    }

    io::printfn("Environment: %s (%s)", env_ptr.name, env_id);
    io::printfn("Modules: %s", string::join(tmem, resolved.to_tarray(), ", "));
    io::printn("");

    String family = plat.distro_family;
    if (family != "arch" && family != "debian")
    {
        io::printfn("No package manager adapter for this platform (detected: %s)", family);
        return 3;
    }

    List{String} module_dirs;
    module_dirs.tinit();
    foreach (id : resolved)
    {
        module_dirs.push(string::tformat("%s/modules/%s", config_root, id));
    }

    List{package::PackageRef} plan = package::plan(module_dirs.to_tarray(), family);
    List{String} pending_required;
    pending_required.tinit();
    List{String} pending_optional;
    pending_optional.tinit();
    List{String} already_installed;
    already_installed.tinit();
    foreach (p : plan)
    {
        bool installed = family == "arch" ? package_pacman::is_installed(p.name) : package_apt::is_installed(p.name);
        if (installed)
        {
            already_installed.push(p.name);
        }
        else if (p.kind == package::Kind.REQUIRED)
        {
            pending_required.push(p.name);
        }
        else
        {
            pending_optional.push(p.name);
        }
    }

    List{String} aur_pending_required;
    aur_pending_required.tinit();
    List{String} aur_pending_optional;
    aur_pending_optional.tinit();
    List{String} aur_already_installed;
    aur_already_installed.tinit();
    String aur_helper = "";
    if (family == "arch")
    {
        List{package::PackageRef} aur_plan = package::plan(module_dirs.to_tarray(), "aur");
        foreach (p : aur_plan)
        {
            bool installed = aur::is_installed(p.name);
            if (installed)
            {
                aur_already_installed.push(p.name);
            }
            else if (p.kind == package::Kind.REQUIRED)
            {
                aur_pending_required.push(p.name);
            }
            else
            {
                aur_pending_optional.push(p.name);
            }
        }
        String? h = aur::detect_helper();
        if (try hh = h) aur_helper = hh;
    }

    io::printfn("Package plan (%s)", family);
    print_package_list("Already installed", already_installed.to_tarray());
    print_package_list("To install (required)", pending_required.to_tarray());
    print_package_list("To install (optional)", pending_optional.to_tarray());
    bool has_aur = aur_pending_required.len() > 0 || aur_pending_optional.len() > 0 || aur_already_installed.len() > 0;
    if (has_aur)
    {
        io::printn("");
        io::printn("AUR package plan");
        if (aur_helper.len > 0)
        {
            io::printfn("  Helper: %s", aur_helper);
        }
        else
        {
            io::printn("  Warning: no AUR helper (paru/yay) found");
        }
        print_package_list("Already installed", aur_already_installed.to_tarray());
        print_package_list("To install (required)", aur_pending_required.to_tarray());
        print_package_list("To install (optional)", aur_pending_optional.to_tarray());
        if (aur_helper.len == 0 && aur_pending_required.len() > 0)
        {
            io::printn("");
            io::printn(aur::bootstrap_instructions());
        }
    }
    io::printn("");

    String home = home_dir();

    if (dry_run)
    {
        io::printn("File deployment");
        foreach (id : resolved)
        {
            String module_dir = string::tformat("%s/modules/%s", config_root, id);
            dsl::ModuleDecl* decl = md.modules.find(id)!!;
            List{module_links::LinkPlan} lps = module_links::resolve(module_dir, decl, home);
            foreach (lp : lps)
            {
                symlink::Result r = symlink::deploy(lp.source, lp.target, true);
                io::printfn("  %s [%s] %s", lp.target, r.status, r.detail);
            }
        }
        io::printn("");
        io::printn("Dry run: no packages installed, no files changed, no state changed.");
        return 0;
    }

    bool nothing_pending = pending_required.len() == 0 && pending_optional.len() == 0
        && aur_pending_required.len() == 0 && aur_pending_optional.len() == 0;

    if (!nothing_pending && !assume_yes)
    {
        if (!prompt::confirm("Proceed with this plan?", false))
        {
            io::printn("Aborted.");
            return 1;
        }
    }

    bool required_failed = false;
    bool optional_failed = false;
    bool aur_required_failed = false;

    if (!nothing_pending)
    {
        bool sync_ok = true;
        if (family == "arch")
        {
            if (catch package_pacman::sync()) sync_ok = false;
        }
        else
        {
            if (catch package_apt::update()) sync_ok = false;
        }
        if (!sync_ok)
        {
            io::printn("Package database sync failed; see output above.");
            return 1;
        }

        if (pending_required.len() > 0)
        {
            if (family == "arch")
            {
                if (catch package_pacman::install(pending_required.to_tarray())) required_failed = true;
            }
            else
            {
                if (catch package_apt::install(pending_required.to_tarray())) required_failed = true;
            }
        }
        if (pending_optional.len() > 0)
        {
            if (family == "arch")
            {
                if (catch package_pacman::install(pending_optional.to_tarray())) optional_failed = true;
            }
            else
            {
                if (catch package_apt::install(pending_optional.to_tarray())) optional_failed = true;
            }
        }
        if (aur_helper.len > 0)
        {
            if (aur_pending_required.len() > 0)
            {
                if (catch aur::install(aur_pending_required.to_tarray())) aur_required_failed = true;
            }
            if (aur_pending_optional.len() > 0)
            {
                if (catch aur::install(aur_pending_optional.to_tarray())) optional_failed = true;
            }
        }
        else if (aur_pending_required.len() > 0)
        {
            aur_required_failed = true;
        }
    }

    io::printn("");
    io::printn("File deployment");
    bool files_failed = false;
    foreach (id : resolved)
    {
        String module_dir = string::tformat("%s/modules/%s", config_root, id);
        dsl::ModuleDecl* decl = md.modules.find(id)!!;
        List{module_links::LinkPlan} lps = module_links::resolve(module_dir, decl, home);
        foreach (lp : lps)
        {
            symlink::Result r = symlink::deploy(lp.source, lp.target);
            if (r.status == symlink::Status.FAILED) files_failed = true;
            io::printfn("  %s [%s] %s", lp.target, r.status, r.detail);
        }
    }

    io::printn("");
    local_values::LocalValues? values = local_values::ensure_for_environment(env_ptr, xdg::local_env_file());

    if (try v = values)
    {
        String? name = v.get("GIT_NAME");
        String? email = v.get("GIT_EMAIL");
        if (try n = name)
        {
            if (try e = email)
            {
                if (n.len > 0 && e.len > 0)
                {
                    io::printn("");
                    io::printn("Git identity");
                    git_identity::Status? gs = git_identity::ensure_identity(n, e, xdg::git_local_inc_path());
                    if (try g = gs)
                    {
                        io::printfn("  %s: %s", xdg::git_local_inc_path(), g);
                    }
                }
            }
        }
    }

    if (!non_interactive)
    {
        io::printn("");
        io::printn("SSH");
        String comment = "";
        if (try v = values)
        {
            String? email = v.get("GIT_EMAIL");
            if (try e = email) comment = e;
        }
        ssh::ensure_key_interactive(ssh::default_ssh_dir(), comment, non_interactive);
    }

    List{dsl::ManualTaskDecl} tasks;
    tasks.tinit();
    tasks.push(manual_tasks::builtin_git_identity());
    tasks.push(manual_tasks::builtin_github_ssh_key());
    foreach (id : resolved)
    {
        String module_dir = string::tformat("%s/modules/%s", config_root, id);
        dsl::ManualTasksParse p = manual_tasks::discover_module_tasks(module_dir);
        tasks.push_all(p.tasks.to_tarray());
    }
    io::printn("");
    manual_tasks::render_checklist(tasks.to_tarray(), xdg::manual_tasks_state_file());

    (void)save_default_environment(env_id);

    io::printn("");
    io::printn("Summary");
    io::printn("");
    if (required_failed || aur_required_failed)
    {
        io::printn("One or more required packages failed to install; see output above.");
    }
    else
    {
        io::printn("Required packages installed.");
    }
    if (optional_failed)
    {
        io::printn("One or more optional packages failed to install; see output above.");
    }
    if (files_failed)
    {
        io::printn("One or more files failed to deploy; see output above.");
    }
    else
    {
        io::printn("Files deployed.");
    }
    if (manual_tasks::has_pending_required(tasks.to_tarray(), xdg::manual_tasks_state_file()))
    {
        io::printn("One or more required manual tasks are still pending; see checklist above.");
    }

    if (required_failed || aur_required_failed || files_failed) return 1;
    return 0;
}
