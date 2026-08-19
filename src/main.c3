module machine_config_manager;
import machine_config_manager::discover;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import std::io;
import std::collections::list;

fn int main(String[] args)
{
    if (args.len < 2)
    {
        io::printn("Usage: machine-config-manager <command> [args]");
        io::printn("Commands:");
        io::printn("  validate [--config-root PATH]");
        return 64;
    }

    switch (args[1])
    {
        case "validate":
            return cmd_validate(args[2..]);
        default:
            io::printfn("Unknown command: %s", args[1]);
            return 64;
    }
}

fn int cmd_validate(String[] args)
{
    String config_root = ".";
    for (usz i = 0; i < args.len; i++)
    {
        if (args[i] == "--config-root" && i + 1 < args.len)
        {
            config_root = args[i + 1];
            i++;
        }
    }

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
