module machine_config_manager::dsl;
import std::io;
import std::collections::list;

<*
 Parsed form of a modules/<id>/module.mcm file. Field-for-field match with
 the Bash DSL's mod_* declarations (docs/module-authoring.md in
 machine-config), plus two new fields the Bash DSL doesn't have:

 - from_module (FROM): Docker-style single-parent inheritance. Empty means
   no parent. Merging the parent's fields into this one happens during
   registry resolution (needs every module loaded first to detect unknown
   targets/cycles) — a single file's parse never resolves it.
 - link (LINK): explicit symlink-target overrides. Empty means "link every
   file under files/ individually" (the safe default — resolution's job,
   not the parser's, same reason as from_module); one or more LINK lines
   means exactly those paths, same semantics as the old standalone `links`
   file.
*>
struct ModuleDecl
{
    String id;
    String name;
    String description;
    String from_module;
    List{String} supports_distribution;
    List{String} excludes_distribution;
    List{String} requires;
    List{String} excludes;
    List{String} link;
}

struct ModuleParse
{
    ModuleDecl decl;
    List{String} errors;
}

fn ModuleDecl module_decl_init()
{
    ModuleDecl m;
    m.supports_distribution.tinit();
    m.excludes_distribution.tinit();
    m.requires.tinit();
    m.excludes.tinit();
    m.link.tinit();
    return m;
}

<*
 Parses one module.mcm file's contents. `default_id` is the module's
 directory basename — ID is optional in the file and defaults to it; if
 ID is present it must still match (same invariant as today's Bash
 implementation, just an assertion now instead of a requirement).

 Permissive like the Bash implementation's mc_module_load_file: a bad line
 (unknown keyword, duplicate ID) is recorded in .errors rather than
 aborting the parse, so every problem in a file is reported in one pass
 instead of just the first.
*>
fn ModuleParse parse_module(String source, String default_id)
{
    List{Line} lines = dsl::lex(source);
    defer lines.free();

    ModuleDecl m = module_decl_init();
    List{String} errors;
    errors.tinit();
    bool have_id = false;
    bool have_from = false;

    foreach (l : lines)
    {
        switch (l.keyword)
        {
            case "ID":
                if (have_id)
                {
                    errors.push(string::tformat("line %d: duplicate ID (already set)", l.line_no));
                    continue;
                }
                if (l.rest.len == 0)
                {
                    errors.push(string::tformat("line %d: ID requires a value", l.line_no));
                    continue;
                }
                m.id = l.rest;
                have_id = true;
            case "NAME":
                m.name = l.rest;
            case "DESCRIPTION":
                m.description = l.rest;
            case "FROM":
                if (have_from)
                {
                    errors.push(string::tformat("line %d: duplicate FROM (only one parent module is supported)", l.line_no));
                    continue;
                }
                if (l.rest.len == 0)
                {
                    errors.push(string::tformat("line %d: FROM requires a module id", l.line_no));
                    continue;
                }
                m.from_module = l.rest;
                have_from = true;
            case "SUPPORTS":
                dsl::push_words(&m.supports_distribution, l.rest);
            case "EXCLUDES_DISTRO":
                dsl::push_words(&m.excludes_distribution, l.rest);
            case "REQUIRES":
                dsl::push_words(&m.requires, l.rest);
            case "EXCLUDES":
                dsl::push_words(&m.excludes, l.rest);
            case "LINK":
                dsl::push_words(&m.link, l.rest);
            default:
                errors.push(string::tformat("line %d: unknown keyword \"%s\"", l.line_no, l.keyword));
        }
    }

    if (!have_id)
    {
        m.id = default_id;
    }
    if (!dsl::is_valid_id(m.id))
    {
        errors.push(string::tformat("invalid id \"%s\" (must match ^[a-z][a-z0-9_-]*$)", m.id));
    }
    else if (m.id != default_id)
    {
        errors.push(string::tformat("id \"%s\" does not match its directory name \"%s\"", m.id, default_id));
    }

    if (m.name.len == 0) m.name = m.id;

    return { m, errors };
}
