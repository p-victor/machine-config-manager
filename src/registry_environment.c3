module machine_config_manager::registry;
import machine_config_manager::dsl;
import std::collections::list;
import std::io;

faultdef ENVIRONMENT_NOT_FOUND;

<*
 Every environment discovered under a config root's environments/
 directory, keyed by EnvironmentDecl.id (== the file's basename). Same
 unconditional-registration philosophy as ModuleRegistry.
*>
struct EnvironmentRegistry
{
    List{dsl::EnvironmentDecl} environments;
}

fn EnvironmentRegistry environment_registry_init()
{
    EnvironmentRegistry r;
    r.environments.tinit();
    return r;
}

fn void EnvironmentRegistry.add(&self, dsl::EnvironmentDecl e)
{
    self.environments.push(e);
}

fn dsl::EnvironmentDecl*? EnvironmentRegistry.find(&self, String id)
{
    foreach (&e : self.environments)
    {
        if (e.id == id) return e;
    }
    return ENVIRONMENT_NOT_FOUND~;
}

<*
 Resolves one environment's full enabled-module list by walking its
 EXTENDS chain — ancestors' ENABLE lists first (in EXTENDS declaration
 order, each ancestor visited once even under a diamond), then this
 environment's own, deduped by module id. Same algorithm and ordering as
 lib/environment.sh's mc_environment_resolve_modules /
 mc_environment_walk_modules. Unknown EXTENDS targets and EXTENDS cycles
 are pushed to `errors`; walking continues past either.
*>
fn List{String} resolve_extends_modules(EnvironmentRegistry* reg, String id, List{String}* errors)
{
    List{String} result;
    result.tinit();
    List{String} seen;
    seen.tinit();
    defer seen.free();
    List{String} path;
    path.tinit();
    defer path.free();

    walk_extends(reg, id, &path, &seen, &result, errors);
    return result;
}

fn void walk_extends(EnvironmentRegistry* reg, String id, List{String}* path, List{String}* seen, List{String}* result, List{String}* errors)
{
    if (path.contains(id))
    {
        errors.push(string::tformat("circular environment inheritance: %s -> %s", string::join(tmem, path.to_tarray(), " -> "), id));
        return;
    }

    dsl::EnvironmentDecl*? found = reg.find(id);
    if (catch found)
    {
        errors.push(string::tformat("unknown environment \"%s\"", id));
        return;
    }
    dsl::EnvironmentDecl self_decl = *found;

    path.push(id);
    foreach (parent : self_decl.extends)
    {
        walk_extends(reg, parent, path, seen, result, errors);
    }
    path.pop()!!;

    foreach (mod : self_decl.enable)
    {
        if (!seen.contains(mod))
        {
            result.push(mod);
            seen.push(mod);
        }
    }
}

<*
 Records an error for every EXTENDS target across the whole registry that
 wasn't discovered — the permissive-discovery counterpart to
 resolve_extends_modules's per-environment walk, for `validate` to report
 every dangling reference in a config root in one pass rather than only
 the one belonging to whichever environment happens to get resolved.
*>
fn List{String} validate_extends_refs(EnvironmentRegistry* reg)
{
    List{String} errors;
    errors.tinit();
    foreach (&e : reg.environments)
    {
        foreach (parent : e.extends)
        {
            if (catch reg.find(parent))
            {
                errors.push(string::tformat("environment \"%s\" extends unknown environment \"%s\"", e.id, parent));
            }
        }
    }
    return errors;
}

<*
 Records an error for every ENABLE target across the whole registry that
 isn't a known module — same permissive, whole-registry-in-one-pass idea
 as validate_extends_refs.
*>
fn List{String} validate_enable_refs(EnvironmentRegistry* reg, ModuleRegistry* modules)
{
    List{String} errors;
    errors.tinit();
    foreach (&e : reg.environments)
    {
        foreach (mod : e.enable)
        {
            if (catch modules.find(mod))
            {
                errors.push(string::tformat("environment \"%s\" enables unknown module \"%s\"", e.id, mod));
            }
        }
    }
    return errors;
}
