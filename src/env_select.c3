module machine_config_manager::env_select;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import machine_config_manager::prompt;
import std::io;
import std::collections::list;

faultdef INVALID_SELECTION;

<* Empty list = unrestricted (matches every value), same as every other SUPPORTS_*-style field in this project. *>
fn bool list_allows(List{String}* list, String value)
{
    if (list.len() == 0) return true;
    foreach (x : list.to_tarray())
    {
        if (x == value) return true;
    }
    return false;
}

<*
 Checks SUPPORTS_DISTRO/SUPPORTS_CONTEXT/SUPPORTS_ARCH against the
 detected platform — same as commands/install.sh's
 mc_install_environment_compatible.
*>
fn bool is_compatible(dsl::EnvironmentDecl* e, String distro_id, String context, String arch)
{
    return list_allows(&e.supports_distribution, distro_id)
        && list_allows(&e.supports_context, context)
        && list_allows(&e.supports_architecture, arch);
}

struct Candidate
{
    String id;
    int order;
}

<*
 Discovered, non-hidden, platform-compatible environment ids, sorted by
 ORDER only — ties keep their original discovery order (a stable sort,
 same as commands/install.sh's `sort -n -k1,1 -s`, not a secondary
 alphabetical-by-id sort despite what a first read of "then id" in that
 file's comment might suggest).
*>
fn List{String} compatible_ids(registry::EnvironmentRegistry* reg, String distro_id, String context, String arch)
{
    List{Candidate} candidates;
    candidates.tinit();
    foreach (&e : reg.environments)
    {
        if (e.hidden) continue;
        if (!is_compatible(e, distro_id, context, arch)) continue;
        candidates.push({ e.id, e.order });
    }

    // Stable insertion sort by .order only.
    for (sz i = 1; i < candidates.len(); i++)
    {
        Candidate key = candidates[i];
        sz j = i - 1;
        while (j >= 0 && candidates[j].order > key.order)
        {
            candidates.set(j + 1, candidates[j]);
            j--;
        }
        candidates.set(j + 1, key);
    }

    List{String} ids;
    ids.tinit();
    foreach (c : candidates.to_tarray())
    {
        ids.push(c.id);
    }
    return ids;
}

<*
 Numbered menu over an already-computed `ids` list (see compatible_ids) —
 prompts once, returns the chosen id. A closed/unreadable stdin or an
 out-of-range/non-numeric answer both fail with INVALID_SELECTION;
 callers decide what that means for them (usually: die with a clear
 message).
*>
fn String? select_interactive(registry::EnvironmentRegistry* reg, List{String}* ids)
{
    io::printn("Choose an environment:");
    for (sz i = 0; i < ids.len(); i++)
    {
        dsl::EnvironmentDecl* e = reg.find((*ids)[i])!;
        io::printfn("  %d) %s - %s", i + 1, e.name, e.description);
    }
    String answer = prompt::input("Enter a number")!;
    int? n = answer.trim().to_int();
    if (catch n) return INVALID_SELECTION~;
    if (n < 1 || n > ids.len()) return INVALID_SELECTION~;
    return (*ids)[(sz)(n - 1)];
}
