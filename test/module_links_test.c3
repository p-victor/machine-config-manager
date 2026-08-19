module machine_config_manager::module_links;
import machine_config_manager::dsl;
import std::io;
import std::io::path;
import std::io::file;
import std::collections::list;

fn String workspace(String name)
{
    String dir = string::tformat("/tmp/mcm-module-links-test-%s", name);
    (void)path::rmtree(path::tnew(dir)!!);
    (void)path::mkdir(dir, true);
    return dir;
}

fn void test_resolve_implicit_links_every_file_individually() @test
{
    String base = workspace("implicit");
    String module_dir = string::tformat("%s/modules/nvim", base);
    (void)path::mkdir(string::tformat("%s/files/.config/nvim/lua", module_dir), true);
    file::save(string::tformat("%s/files/.config/nvim/init.lua", module_dir), "x")!!;
    file::save(string::tformat("%s/files/.config/nvim/lua/plugins.lua", module_dir), "y")!!;

    dsl::ModuleDecl m = dsl::module_decl_init();
    m.id = "nvim";
    String home = string::tformat("%s/home", base);

    List{LinkPlan} plans = resolve(module_dir, &m, home);
    test::eq(plans.len(), 2);

    bool saw_init = false;
    bool saw_plugins = false;
    foreach (p : plans)
    {
        if (p.target == string::tformat("%s/.config/nvim/init.lua", home))
        {
            saw_init = true;
            test::eq(p.source, string::tformat("%s/files/.config/nvim/init.lua", module_dir));
        }
        if (p.target == string::tformat("%s/.config/nvim/lua/plugins.lua", home)) saw_plugins = true;
    }
    test::eq(saw_init, true);
    test::eq(saw_plugins, true);
}

fn void test_resolve_explicit_link_whole_directory() @test
{
    String base = workspace("explicit");
    String module_dir = string::tformat("%s/modules/nvim", base);
    (void)path::mkdir(string::tformat("%s/files/.config/nvim", module_dir), true);
    file::save(string::tformat("%s/files/.config/nvim/init.lua", module_dir), "x")!!;

    dsl::ModuleDecl m = dsl::module_decl_init();
    m.id = "nvim";
    m.link.push(".config/nvim");
    String home = string::tformat("%s/home", base);

    List{LinkPlan} plans = resolve(module_dir, &m, home);
    // Exactly the one declared path — not expanded into the files
    // beneath it, unlike the implicit case above.
    test::eq(plans.len(), 1);
    test::eq(plans[0].source, string::tformat("%s/files/.config/nvim", module_dir));
    test::eq(plans[0].target, string::tformat("%s/.config/nvim", home));
}

fn void test_resolve_explicit_link_partial_directory() @test
{
    // The VS Code case: only specific files inside a directory, not the
    // whole thing.
    String base = workspace("partial");
    String module_dir = string::tformat("%s/modules/vscode", base);
    (void)path::mkdir(string::tformat("%s/files/.config/Code/User", module_dir), true);
    file::save(string::tformat("%s/files/.config/Code/User/settings.json", module_dir), "{}")!!;
    file::save(string::tformat("%s/files/.config/Code/User/keybindings.json", module_dir), "{}")!!;

    dsl::ModuleDecl m = dsl::module_decl_init();
    m.id = "vscode";
    m.link.push(".config/Code/User/settings.json");
    String home = string::tformat("%s/home", base);

    List{LinkPlan} plans = resolve(module_dir, &m, home);
    test::eq(plans.len(), 1);
    test::eq(plans[0].target, string::tformat("%s/.config/Code/User/settings.json", home));
}

fn void test_resolve_no_files_dir_is_empty_not_error() @test
{
    String base = workspace("nofiles");
    String module_dir = string::tformat("%s/modules/shell", base);
    (void)path::mkdir(module_dir, true);

    dsl::ModuleDecl m = dsl::module_decl_init();
    m.id = "shell";
    String home = string::tformat("%s/home", base);

    List{LinkPlan} plans = resolve(module_dir, &m, home);
    test::eq(plans.len(), 0);
}
