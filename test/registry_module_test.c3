module machine_config_manager::registry;
import machine_config_manager::dsl;
import std::io;
import std::collections::list;

fn dsl::ModuleDecl mk(String id, String from = "", String[] supports = {}, String[] requires = {}, String[] excludes = {}, String[] link = {})
{
    dsl::ModuleDecl m = dsl::module_decl_init();
    m.id = id;
    m.name = id;
    m.from_module = from;
    m.supports_distribution.push_all(supports);
    m.requires.push_all(requires);
    m.excludes.push_all(excludes);
    m.link.push_all(link);
    return m;
}

fn void test_find_missing() @test
{
    ModuleRegistry reg = module_registry_init();
    if (catch reg.find("nope"))
    {
        return; // expected
    }
    test::@check(false, "expected MODULE_NOT_FOUND");
}

fn void test_find_present() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("shell"));
    dsl::ModuleDecl* found = reg.find("shell")!!;
    test::eq(found.id, "shell");
}

fn void test_resolve_no_from_is_identity() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("shell", "", { "arch", "ubuntu" }));

    List{String} errors;
    errors.tinit();
    dsl::ModuleDecl resolved = resolve_module(&reg, "shell", &errors);
    test::eq(errors.len(), 0);
    test::eq(resolved.supports_distribution.len(), 2);
}

fn void test_resolve_from_merges_parent_then_own() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("_base", "", { "arch" }, {}, {}, { ".config/base" }));
    reg.add(mk("nvim", "_base", { "ubuntu" }, {}, {}, { ".config/nvim" }));

    List{String} errors;
    errors.tinit();
    dsl::ModuleDecl resolved = resolve_module(&reg, "nvim", &errors);
    test::eq(errors.len(), 0);
    test::eq(resolved.id, "nvim"); // identity is never inherited
    test::eq(resolved.supports_distribution.len(), 2);
    test::eq(resolved.supports_distribution[0], "arch");  // parent first
    test::eq(resolved.supports_distribution[1], "ubuntu"); // then own
    test::eq(resolved.link.len(), 2);
    test::eq(resolved.link[0], ".config/base");
    test::eq(resolved.link[1], ".config/nvim");
}

fn void test_resolve_from_unknown_target() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("nvim", "does-not-exist"));

    List{String} errors;
    errors.tinit();
    resolve_module(&reg, "nvim", &errors);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("unknown module"), "got: %s", errors[0]);
}

fn void test_resolve_from_cycle() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("a", "b"));
    reg.add(mk("b", "a"));

    List{String} errors;
    errors.tinit();
    resolve_module(&reg, "a", &errors);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("circular FROM"), "got: %s", errors[0]);
}

fn void test_expand_requires_transitive() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("shell"));
    reg.add(mk("git", "", {}, { "shell" }));
    reg.add(mk("nvim", "", {}, { "shell" }));
    reg.add(mk("vscode", "", {}, { "git", "nvim" }));

    List{String} errors;
    errors.tinit();
    List{String} resolved = expand_requires(&reg, { "vscode" }, &errors);
    test::eq(errors.len(), 0);
    // dependency-then-self order, deduped: shell only appears once even
    // though both git and nvim require it.
    test::eq(resolved.len(), 4);
    test::eq(resolved[0], "shell");
    test::eq(resolved[3], "vscode");
}

fn void test_expand_requires_unknown_target() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("vscode", "", {}, { "ghost" }));

    List{String} errors;
    errors.tinit();
    expand_requires(&reg, { "vscode" }, &errors);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("unknown module"), "got: %s", errors[0]);
}

fn void test_expand_requires_cycle() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("a", "", {}, { "b" }));
    reg.add(mk("b", "", {}, { "a" }));

    List{String} errors;
    errors.tinit();
    expand_requires(&reg, { "a" }, &errors);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("circular module dependency"), "got: %s", errors[0]);
}

fn void test_expand_requires_picks_up_from_inherited_requires() @test
{
    // A REQUIRES declared on a FROM-parent is inherited, so expanding a
    // child that never wrote its own REQUIRES still pulls the parent's in.
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("shell"));
    reg.add(mk("_base", "", {}, { "shell" }));
    reg.add(mk("nvim", "_base"));

    List{String} errors;
    errors.tinit();
    List{String} resolved = expand_requires(&reg, { "nvim" }, &errors);
    test::eq(errors.len(), 0);
    test::eq(resolved.len(), 2);
    test::eq(resolved[0], "shell");
    test::eq(resolved[1], "nvim");
}

fn void test_find_conflicts_none() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("a"));
    reg.add(mk("b"));
    List{ConflictPair} c = find_conflicts(&reg, { "a", "b" });
    test::eq(c.len(), 0);
}

fn void test_find_conflicts_detected_either_direction() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("a", "", {}, {}, { "b" })); // a excludes b
    reg.add(mk("b"));
    reg.add(mk("c", "", {}, {}, {}));
    List{ConflictPair} c = find_conflicts(&reg, { "a", "b", "c" });
    test::eq(c.len(), 1);
    test::eq(c[0].a, "a");
    test::eq(c[0].b, "b");
}

fn void test_paths_conflict_exact_and_nested() @test
{
    test::eq(paths_conflict(".config/nvim", ".config/nvim"), true);
    test::eq(paths_conflict(".config/nvim", ".config/nvim/lua"), true);
    test::eq(paths_conflict(".config/nvim/lua", ".config/nvim"), true);
    test::eq(paths_conflict(".config/nvim", ".config/nvim2"), false);
    test::eq(paths_conflict(".config/nvim", ".config/git"), false);
}

fn void test_find_link_conflicts_none() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("nvim", "", {}, {}, {}, { ".config/nvim" }));
    reg.add(mk("git", "", {}, {}, {}, { ".config/git" }));
    List{LinkConflict} c = find_link_conflicts(&reg, { "nvim", "git" });
    test::eq(c.len(), 0);
}

fn void test_find_link_conflicts_exact_duplicate() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("nvim", "", {}, {}, {}, { ".config/nvim" }));
    reg.add(mk("nvim-fork", "", {}, {}, {}, { ".config/nvim" }));
    List{LinkConflict} c = find_link_conflicts(&reg, { "nvim", "nvim-fork" });
    test::eq(c.len(), 1);
    test::eq(c[0].module_a, "nvim");
    test::eq(c[0].path_a, ".config/nvim");
    test::eq(c[0].module_b, "nvim-fork");
}

fn void test_find_link_conflicts_nested_path() @test
{
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("nvim", "", {}, {}, {}, { ".config/nvim" }));
    reg.add(mk("nvim-lua-extra", "", {}, {}, {}, { ".config/nvim/lua" }));
    List{LinkConflict} c = find_link_conflicts(&reg, { "nvim", "nvim-lua-extra" });
    test::eq(c.len(), 1);
}

fn void test_find_link_conflicts_inherited_via_from() @test
{
    // A conflict introduced through a FROM-inherited LINK is still caught
    // — find_link_conflicts operates on resolved (post-FROM) decls.
    ModuleRegistry reg = module_registry_init();
    reg.add(mk("_base", "", {}, {}, {}, { ".config/shared" }));
    reg.add(mk("a", "_base"));
    reg.add(mk("b", "", {}, {}, {}, { ".config/shared" }));
    List{LinkConflict} c = find_link_conflicts(&reg, { "a", "b" });
    test::eq(c.len(), 1);
}
