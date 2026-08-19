module machine_config_manager::dsl;
import std::io;
import std::collections::list;

<*
 One REQUIRE_LOCAL default: DEFAULT_LOCAL EDITOR nvim -> {name: "EDITOR",
 value: "nvim"}. Matches env_default_local_value's two-argument form.
*>
struct DefaultLocal
{
    String name;
    String value;
}

<*
 Parsed form of an environments/<id>.mcm file. Field-for-field match with
 the Bash DSL's env_* declarations (docs/environment-authoring.md in
 machine-config).
*>
struct EnvironmentDecl
{
    String id;
    String name;
    String description;
    int order;
    bool hidden;
    bool deprecated;
    List{String} supports_distribution;
    List{String} supports_context;
    List{String} supports_architecture;
    List{String} extends;
    List{String} enable;
    List{String} require_local;
    List{DefaultLocal} default_local;
}

struct EnvironmentParse
{
    EnvironmentDecl decl;
    List{String} errors;
}

fn EnvironmentDecl environment_decl_init()
{
    EnvironmentDecl e;
    e.order = 100;
    e.supports_distribution.tinit();
    e.supports_context.tinit();
    e.supports_architecture.tinit();
    e.extends.tinit();
    e.enable.tinit();
    e.require_local.tinit();
    e.default_local.tinit();
    return e;
}

<*
 Splits "NAME VALUE..." into (name, value) on the first space, taking the
 rest of the line as value (so a value may itself contain spaces). Used by
 DEFAULT_LOCAL only — every other multi-value keyword is a flat word list
 (see push_words).
*>
fn void? split_name_value(String rest, String* name, String* value)
{
    sz sp = rest.index_of_char(' ')!;
    *name = rest[0..sp - 1];
    *value = rest[sp + 1..].trim();
}

<*
 Parses one environments/<id>.mcm file's contents. `default_id` is the
 file's basename (without .mcm) — ID is optional and defaults to it, same
 inference/assertion rule as parse_module's `default_id`. Same permissive
 style as parse_module: records problems in .errors, keeps going.
*>
fn EnvironmentParse parse_environment(String source, String default_id)
{
    List{Line} lines = dsl::lex(source);
    defer lines.free();

    EnvironmentDecl e = environment_decl_init();
    List{String} errors;
    errors.tinit();
    bool have_id = false;

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
                e.id = l.rest;
                have_id = true;
            case "NAME":
                e.name = l.rest;
            case "DESCRIPTION":
                e.description = l.rest;
            case "ORDER":
                int? order = l.rest.to_int();
                if (catch order)
                {
                    errors.push(string::tformat("line %d: ORDER value \"%s\" is not an integer", l.line_no, l.rest));
                }
                else
                {
                    e.order = order;
                }
            case "HIDDEN":
                e.hidden = true;
            case "DEPRECATED":
                e.deprecated = true;
            case "SUPPORTS_DISTRO":
                dsl::push_words(&e.supports_distribution, l.rest);
            case "SUPPORTS_CONTEXT":
                dsl::push_words(&e.supports_context, l.rest);
            case "SUPPORTS_ARCH":
                dsl::push_words(&e.supports_architecture, l.rest);
            case "EXTENDS":
                dsl::push_words(&e.extends, l.rest);
            case "ENABLE":
                foreach (w : l.rest.tsplit(" ", skip_empty: true))
                {
                    if (w.len == 0) continue;
                    if (e.enable.contains(w))
                    {
                        errors.push(string::tformat("line %d: duplicate ENABLE \"%s\"", l.line_no, w));
                        continue;
                    }
                    e.enable.push(w);
                }
            case "REQUIRE_LOCAL":
                dsl::push_words(&e.require_local, l.rest);
            case "DEFAULT_LOCAL":
                String dl_name;
                String dl_value;
                if (catch split_name_value(l.rest, &dl_name, &dl_value))
                {
                    errors.push(string::tformat("line %d: DEFAULT_LOCAL requires a name and a value", l.line_no));
                }
                else
                {
                    e.default_local.push({ dl_name, dl_value });
                }
            default:
                errors.push(string::tformat("line %d: unknown keyword \"%s\"", l.line_no, l.keyword));
        }
    }

    if (!have_id)
    {
        e.id = default_id;
    }
    if (!dsl::is_valid_id(e.id))
    {
        errors.push(string::tformat("invalid id \"%s\" (must match ^[a-z][a-z0-9_-]*$)", e.id));
    }
    else if (e.id != default_id)
    {
        errors.push(string::tformat("id \"%s\" does not match its filename \"%s\"", e.id, default_id));
    }

    if (e.name.len == 0) e.name = e.id;

    return { e, errors };
}
