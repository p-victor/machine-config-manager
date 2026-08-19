module machine_config_manager::module_links;
import machine_config_manager::dsl;
import std::io;
import std::io::path;
import std::collections::list;

<*
 One deploy pair for symlink.c3::deploy: `source` (absolute, under a
 module's files/) -> `target` (absolute, under $HOME).
*>
struct LinkPlan
{
    String source;
    String target;
}

<*
 Computes what a module would actually deploy — the filesystem-aware half
 of the LINK design (dsl_module.c3's doc comment): explicit LINK lines
 are used as-is (module owns exactly those paths, verbatim); with no LINK
 lines at all, every regular file under modules/<id>/files/ is walked and
 linked individually (the safe default — never infers "this whole
 directory belongs to the module"). A module with neither LINK lines nor
 a files/ directory deploys nothing, not an error (e.g. a module that's
 purely packages, like a CLI tool with no dotfiles).
*>
fn List{LinkPlan} resolve(String module_dir, dsl::ModuleDecl* mod, String home_dir)
{
    List{LinkPlan} plans;
    plans.tinit();

    if (mod.link.len() > 0)
    {
        foreach (p : mod.link)
        {
            plans.push({
                string::tformat("%s/files/%s", module_dir, p),
                string::tformat("%s/%s", home_dir, p),
            });
        }
        return plans;
    }

    String files_dir = string::tformat("%s/files", module_dir);
    Path? dir = path::tnew(files_dir);
    if (catch dir) return plans;
    if (!path::is_dir(dir)) return plans;

    PathList? entries = path::ls(tmem, dir, no_dirs: true, recursive: true, relative: true);
    if (catch entries) return plans;

    foreach (e : entries)
    {
        String rel = (String)e;
        plans.push({
            string::tformat("%s/%s", files_dir, rel),
            string::tformat("%s/%s", home_dir, rel),
        });
    }
    return plans;
}
