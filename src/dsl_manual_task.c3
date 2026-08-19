module machine_config_manager::dsl;
import std::io;
import std::collections::list;

<*
 Parsed form of one MANUAL_TASK block. Field-for-field match with the
 Bash DSL's mod_manual_task (docs/module-authoring.md) — verify/
 instructions empty means "not declared", same absence-means-unset
 convention as everywhere else in this DSL.
*>
struct ManualTaskDecl
{
    String id;
    String description;
    bool required;
    String verify;
    String instructions;
}

struct ManualTasksParse
{
    List{ManualTaskDecl} tasks;
    List{String} errors;
}

<*
 Parses an instructions/tasks.mcm file: zero or more tasks, each starting
 with a `TASK <id>` line and running until the next `TASK` line or EOF.
 Unlike module.mcm/environment.mcm (one declaration per file), a file
 here can declare several tasks — TASK is the boundary, the same role
 mod_manual_task's single all-in-one-call signature plays in the Bash
 DSL, just spread across lines to match this DSL's one-instruction-
 per-line style.

 `VERIFY -- COMMAND` takes the raw shell command verbatim after the `--`
 marker (Docker's RUN-takes-rest-of-line convention) — it's later run
 standalone via `bash -c`, with no access to this project's own
 functions, same constraint as the Bash implementation's --verify.

 Permissive like every other parser here: a bad task (missing/duplicate
 id, missing description) is recorded in .errors, parsing keeps going.
*>
fn void commit_task(ManualTasksParse* result, ManualTaskDecl* current, bool* have_current, List{String}* seen_ids)
{
    if (!*have_current) return;
    if (current.id.len == 0)
    {
        result.errors.push("MANUAL_TASK declares no id");
    }
    else if (!dsl::is_valid_id(current.id))
    {
        result.errors.push(string::tformat("invalid task id \"%s\" (must match ^[a-z][a-z0-9_-]*$)", current.id));
    }
    else if (seen_ids.contains(current.id))
    {
        result.errors.push(string::tformat("duplicate task id \"%s\"", current.id));
    }
    else if (current.description.len == 0)
    {
        result.errors.push(string::tformat("task \"%s\" declares no DESCRIPTION", current.id));
    }
    else
    {
        seen_ids.push(current.id);
        result.tasks.push(*current);
    }
}

fn ManualTasksParse parse_manual_tasks(String source)
{
    List{Line} lines = dsl::lex(source);
    defer lines.free();

    ManualTasksParse result;
    result.tasks.tinit();
    result.errors.tinit();

    bool have_current = false;
    ManualTaskDecl current;
    List{String} seen_ids;
    seen_ids.tinit();

    foreach (l : lines)
    {
        switch (l.keyword)
        {
            case "TASK":
                commit_task(&result, &current, &have_current, &seen_ids);
                current = { l.rest, "", false, "", "" };
                have_current = true;
            case "DESCRIPTION":
                if (!have_current)
                {
                    result.errors.push(string::tformat("line %d: DESCRIPTION before any TASK", l.line_no));
                    continue;
                }
                current.description = l.rest;
            case "REQUIRED":
                if (!have_current)
                {
                    result.errors.push(string::tformat("line %d: REQUIRED before any TASK", l.line_no));
                    continue;
                }
                current.required = true;
            case "OPTIONAL":
                if (!have_current)
                {
                    result.errors.push(string::tformat("line %d: OPTIONAL before any TASK", l.line_no));
                    continue;
                }
                current.required = false;
            case "VERIFY":
                if (!have_current)
                {
                    result.errors.push(string::tformat("line %d: VERIFY before any TASK", l.line_no));
                    continue;
                }
                if (!l.rest.starts_with("--"))
                {
                    result.errors.push(string::tformat("line %d: VERIFY requires \"-- COMMAND\"", l.line_no));
                    continue;
                }
                current.verify = l.rest[2..].trim();
                if (current.verify.len == 0)
                {
                    result.errors.push(string::tformat("line %d: VERIFY requires a command after --", l.line_no));
                }
            case "INSTRUCTIONS":
                if (!have_current)
                {
                    result.errors.push(string::tformat("line %d: INSTRUCTIONS before any TASK", l.line_no));
                    continue;
                }
                current.instructions = l.rest;
            default:
                result.errors.push(string::tformat("line %d: unknown keyword \"%s\"", l.line_no, l.keyword));
        }
    }
    commit_task(&result, &current, &have_current, &seen_ids);

    return result;
}
