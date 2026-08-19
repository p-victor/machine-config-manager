module machine_config_manager::discover;
import machine_config_manager::dsl;
import machine_config_manager::registry;
import std::io;
import std::io::path;
import std::io::file;
import std::collections::list;

<*
 modules/ discovery result: every modules/<id>/module.mcm found (id is the
 directory name — see dsl::parse_module's default_id), plus every parse
 error found across all of them, each prefixed with its file path so a
 report can point straight at the offending file. A missing modules/
 directory isn't an error (a fresh/minimal config root may not have one
 yet) — same as lib/module.sh's mc_module_discover.
*>
struct ModuleDiscovery
{
    registry::ModuleRegistry modules;
    List{String} errors;
}

fn ModuleDiscovery discover_modules(String config_root)
{
    ModuleDiscovery result;
    result.modules = registry::module_registry_init();
    result.errors.tinit();

    Path? modules_dir = path::tnew(string::tformat("%s/modules", config_root));
    if (catch modules_dir) return result;
    if (!path::is_dir(modules_dir)) return result;

    PathList? entries = path::ls(tmem, modules_dir, relative: false);
    if (catch entries) return result;

    foreach (e : entries)
    {
        if (!path::is_dir(e)) continue;
        String id = e.basename();
        String module_file = string::tformat("%s/module.mcm", (String)e);
        Path? module_path = path::tnew(module_file);
        if (catch module_path) continue;
        if (!path::exists(module_path)) continue;

        char[]? raw = file::load_temp(module_file);
        if (catch raw)
        {
            result.errors.push(string::tformat("%s: failed to read file", module_file));
            continue;
        }
        dsl::ModuleParse p = dsl::parse_module((String)raw, id);
        foreach (err : p.errors)
        {
            result.errors.push(string::tformat("%s: %s", module_file, err));
        }
        result.modules.add(p.decl);
    }
    return result;
}

<*
 environments/*.mcm discovery result — same shape as ModuleDiscovery. The
 environment id is the filename without its .mcm extension (see
 dsl::parse_environment's default_id).
*>
struct EnvironmentDiscovery
{
    registry::EnvironmentRegistry environments;
    List{String} errors;
}

fn EnvironmentDiscovery discover_environments(String config_root)
{
    EnvironmentDiscovery result;
    result.environments = registry::environment_registry_init();
    result.errors.tinit();

    Path? env_dir = path::tnew(string::tformat("%s/environments", config_root));
    if (catch env_dir) return result;
    if (!path::is_dir(env_dir)) return result;

    PathList? entries = path::ls(tmem, env_dir, no_dirs: true, relative: false);
    if (catch entries) return result;

    foreach (e : entries)
    {
        String name = e.basename();
        if (!name.ends_with(".mcm")) continue;
        String id = name.strip_suffix(".mcm");
        String env_file = (String)e;

        char[]? raw = file::load_temp(env_file);
        if (catch raw)
        {
            result.errors.push(string::tformat("%s: failed to read file", env_file));
            continue;
        }
        dsl::EnvironmentParse p = dsl::parse_environment((String)raw, id);
        foreach (err : p.errors)
        {
            result.errors.push(string::tformat("%s: %s", env_file, err));
        }
        result.environments.add(p.decl);
    }
    return result;
}
