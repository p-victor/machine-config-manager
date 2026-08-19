module machine_config_manager::registry;
import machine_config_manager::dsl;
import std::collections::list;
import std::io;

faultdef MODULE_NOT_FOUND;

<*
 Every module discovered under a config root's modules/ directory, keyed
 by ModuleDecl.id (== the module's directory name). Registration is
 unconditional — even a module whose own file had parse errors still gets
 a best-effort entry, so REQUIRES/FROM targets pointing at it can still be
 checked and every problem in a config root shows up in one pass (same
 permissive-discovery philosophy as lib/module.sh's mc_module_discover).
*>
struct ModuleRegistry
{
    List{dsl::ModuleDecl} modules;
}

fn ModuleRegistry module_registry_init()
{
    ModuleRegistry r;
    r.modules.tinit();
    return r;
}

fn void ModuleRegistry.add(&self, dsl::ModuleDecl m)
{
    self.modules.push(m);
}

fn dsl::ModuleDecl*? ModuleRegistry.find(&self, String id)
{
    foreach (&m : self.modules)
    {
        if (m.id == id) return m;
    }
    return MODULE_NOT_FOUND~;
}

<*
 Resolves one module's FROM chain: identity (id/name/description) always
 comes from the module itself, never a parent — only the four list fields
 (SUPPORTS/EXCLUDES_DISTRO/REQUIRES/EXCLUDES/LINK) are inherited, parent's
 entries first then this module's own, same base-layer-then-additions
 idea as a Dockerfile FROM. Unknown FROM targets and FROM cycles are
 pushed to `errors`; resolution stops inheriting at that point but still
 returns a usable (just incomplete) decl rather than aborting the whole
 registry.
*>
fn dsl::ModuleDecl resolve_module(ModuleRegistry* reg, String id, List{String}* errors)
{
    List{String} path;
    path.tinit();
    defer path.free();
    return resolve_module_walk(reg, id, &path, errors);
}

fn dsl::ModuleDecl resolve_module_walk(ModuleRegistry* reg, String id, List{String}* path, List{String}* errors)
{
    if (path.contains(id))
    {
        errors.push(string::tformat("circular FROM: %s -> %s", string::join(tmem, path.to_tarray(), " -> "), id));
        return dsl::module_decl_init();
    }

    dsl::ModuleDecl*? found = reg.find(id);
    if (catch found)
    {
        errors.push(string::tformat("unknown module \"%s\"", id));
        return dsl::module_decl_init();
    }
    dsl::ModuleDecl self_decl = *found;

    dsl::ModuleDecl result = dsl::module_decl_init();
    result.id = self_decl.id;
    result.name = self_decl.name;
    result.description = self_decl.description;
    result.from_module = self_decl.from_module;

    if (self_decl.from_module.len > 0)
    {
        path.push(id);
        dsl::ModuleDecl parent = resolve_module_walk(reg, self_decl.from_module, path, errors);
        path.pop()!!;
        result.supports_distribution.push_all(parent.supports_distribution.to_tarray());
        result.excludes_distribution.push_all(parent.excludes_distribution.to_tarray());
        result.requires.push_all(parent.requires.to_tarray());
        result.excludes.push_all(parent.excludes.to_tarray());
        result.link.push_all(parent.link.to_tarray());
    }

    result.supports_distribution.push_all(self_decl.supports_distribution.to_tarray());
    result.excludes_distribution.push_all(self_decl.excludes_distribution.to_tarray());
    result.requires.push_all(self_decl.requires.to_tarray());
    result.excludes.push_all(self_decl.excludes.to_tarray());
    result.link.push_all(self_decl.link.to_tarray());

    return result;
}

<*
 Expands a seed list of module ids into every module transitively pulled
 in via REQUIRES (post-FROM-resolution requires lists), deduped, in
 dependency-then-self order — same algorithm and ordering as lib/module.sh's
 mc_module_expand_dependencies. Unknown REQUIRES targets and REQUIRES
 cycles are pushed to `errors`; walking continues past either (permissive,
 like everything else at this layer — strict die-on-first-problem belongs
 to a later real-use resolver, not this one).
*>
fn List{String} expand_requires(ModuleRegistry* reg, String[] seeds, List{String}* errors)
{
    List{String} result;
    result.tinit();
    List{String} seen;
    seen.tinit();
    defer seen.free();

    foreach (seed : seeds)
    {
        List{String} path;
        path.tinit();
        defer path.free();
        walk_requires(reg, seed, &path, &seen, &result, errors);
    }
    return result;
}

fn void walk_requires(ModuleRegistry* reg, String id, List{String}* path, List{String}* seen, List{String}* result, List{String}* errors)
{
    if (path.contains(id))
    {
        errors.push(string::tformat("circular module dependency: %s -> %s", string::join(tmem, path.to_tarray(), " -> "), id));
        return;
    }

    if (catch reg.find(id))
    {
        errors.push(string::tformat("unknown module \"%s\"", id));
        return;
    }

    List{String} from_errors;
    from_errors.tinit();
    defer from_errors.free();
    dsl::ModuleDecl resolved = resolve_module(reg, id, &from_errors);

    path.push(id);
    foreach (target : resolved.requires)
    {
        walk_requires(reg, target, path, seen, result, errors);
    }
    path.pop()!!;

    if (!seen.contains(id))
    {
        result.push(id);
        seen.push(id);
    }
}

<*
 Reports every conflicting pair among `ids` (post-FROM EXCLUDES lists,
 checked in both declaration directions) — same as lib/module.sh's
 mc_module_find_conflicts, minus the printf-and-parse-it-back-out
 indirection that exists in Bash only because Bash has no structured
 return values.
*>
struct ConflictPair
{
    String a;
    String b;
}

fn List{ConflictPair} find_conflicts(ModuleRegistry* reg, String[] ids)
{
    List{ConflictPair} conflicts;
    conflicts.tinit();

    for (usz i = 0; i < ids.len; i++)
    {
        for (usz j = i + 1; j < ids.len; j++)
        {
            List{String} ignored;
            ignored.tinit();
            defer ignored.free();
            dsl::ModuleDecl a = resolve_module(reg, ids[i], &ignored);
            dsl::ModuleDecl b = resolve_module(reg, ids[j], &ignored);
            if (a.excludes.contains(ids[j]) || b.excludes.contains(ids[i]))
            {
                conflicts.push({ ids[i], ids[j] });
            }
        }
    }
    return conflicts;
}

<*
 True if `a` and `b` (both $HOME-relative LINK paths) can't both be
 deployed: identical paths, or one a directory ancestor of the other
 (".config/nvim" vs. ".config/nvim/lua" — once the first is a symlink,
 deploying anything "inside" it is nonsensical). Plain string comparison,
 not filesystem-aware — doesn't know or care whether either path is
 actually a directory on disk.
*>
fn bool paths_conflict(String a, String b)
{
    if (a == b) return true;
    if (a.len < b.len) return b.starts_with(string::tformat("%s/", a));
    return a.starts_with(string::tformat("%s/", b));
}

<*
 One pair of modules whose (post-FROM) LINK paths collide, and the
 specific paths that do.
*>
struct LinkConflict
{
    String module_a;
    String path_a;
    String module_b;
    String path_b;
}

<*
 Reports every pair of modules among `ids` that declare overlapping LINK
 paths — the file-deployment counterpart to find_conflicts's EXCLUDES
 check, since two modules that would both try to symlink the same (or a
 nested) $HOME path can never both actually be deployed, whether or not
 they declared each other as EXCLUDES.

 Known gap: only catches conflicts between modules that declare LINK
 explicitly. A module relying on the implicit default (link every file
 under files/ individually, no LINK lines at all) needs the actual
 files/ tree to know what it would deploy — that's filesystem-aware
 resolution for a later phase (install/doctor), not this pure layer.
*>
fn List{LinkConflict} find_link_conflicts(ModuleRegistry* reg, String[] ids)
{
    List{LinkConflict} conflicts;
    conflicts.tinit();

    for (usz i = 0; i < ids.len; i++)
    {
        for (usz j = i + 1; j < ids.len; j++)
        {
            List{String} ignored;
            ignored.tinit();
            defer ignored.free();
            dsl::ModuleDecl a = resolve_module(reg, ids[i], &ignored);
            dsl::ModuleDecl b = resolve_module(reg, ids[j], &ignored);
            foreach (pa : a.link)
            {
                foreach (pb : b.link)
                {
                    if (paths_conflict(pa, pb))
                    {
                        conflicts.push({ ids[i], pa, ids[j], pb });
                    }
                }
            }
        }
    }
    return conflicts;
}
