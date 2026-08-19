module machine_config_manager::package;
import std::io;
import std::io::file;
import std::collections::list;

<*
 Whether a package is a hard requirement or a best-effort extra — see
 docs/module-authoring.md's packages.<family>[.optional] convention.
*>
enum Kind
{
    REQUIRED,
    OPTIONAL,
}

struct PackageRef
{
    String name;
    Kind kind;
}

<*
 One package name per line; `#` starts a comment, blank lines ignored.
 A missing file is an empty list, not an error — a module having no
 packages for a given platform/kind is normal, same as
 lib/package.sh's mc_package_read_list (itself a thin wrapper over
 lib/core.sh's mc_read_list_file).
*>
fn List{String} read_list(String file_path)
{
    List{String} names;
    names.tinit();
    char[]? raw = file::load_temp(file_path);
    if (catch raw) return names;
    foreach (line : ((String)raw).tsplit("\n"))
    {
        String trimmed = line.trim();
        if (trimmed.len == 0) continue;
        if (trimmed[0] == '#') continue;
        names.push(trimmed);
    }
    return names;
}

<*
 One module's required + optional packages for `family` ("arch" or
 "debian") — modules/<id>/packages.<family> and packages.<family>.optional.
*>
fn List{PackageRef} module_package_list(String module_dir, String family)
{
    List{PackageRef} refs;
    refs.tinit();
    foreach (n : read_list(string::tformat("%s/packages.%s", module_dir, family)))
    {
        refs.push({ n, REQUIRED });
    }
    foreach (n : read_list(string::tformat("%s/packages.%s.optional", module_dir, family)))
    {
        refs.push({ n, OPTIONAL });
    }
    return refs;
}

<*
 Deduped plan across every module directory, first-seen order. A package
 required by one module and only optional in another is treated as
 required — the safer default, same as lib/package.sh's mc_package_plan.
*>
fn List{PackageRef} plan(String[] module_dirs, String family)
{
    List{PackageRef} result;
    result.tinit();
    foreach (dir : module_dirs)
    {
        foreach (ref : module_package_list(dir, family))
        {
            bool found = false;
            for (sz i = 0; i < result.len(); i++)
            {
                if (result[i].name == ref.name)
                {
                    found = true;
                    if (ref.kind == REQUIRED) result.set(i, { ref.name, REQUIRED });
                    break;
                }
            }
            if (!found) result.push(ref);
        }
    }
    return result;
}
