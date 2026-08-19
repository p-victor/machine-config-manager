module machine_config_manager::registry;
import machine_config_manager::dsl;
import std::io;
import std::collections::list;

fn dsl::EnvironmentDecl mk_env(String id, String[] extends = {}, String[] enable = {})
{
    dsl::EnvironmentDecl e = dsl::environment_decl_init();
    e.id = id;
    e.name = id;
    e.extends.push_all(extends);
    e.enable.push_all(enable);
    return e;
}

fn void test_env_find_missing() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    if (catch reg.find("nope")) return; // expected
    test::@check(false, "expected ENVIRONMENT_NOT_FOUND");
}

fn void test_resolve_extends_no_parent() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("base", {}, { "shell", "git" }));

    List{String} errors;
    errors.tinit();
    List{String} mods = resolve_extends_modules(&reg, "base", &errors);
    test::eq(errors.len(), 0);
    test::eq(mods.len(), 2);
    test::eq(mods[0], "shell");
    test::eq(mods[1], "git");
}

fn void test_resolve_extends_ancestors_first() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("base", {}, { "shell", "git" }));
    reg.add(mk_env("development", { "base" }, { "nvim", "vscode" }));

    List{String} errors;
    errors.tinit();
    List{String} mods = resolve_extends_modules(&reg, "development", &errors);
    test::eq(errors.len(), 0);
    test::eq(mods.len(), 4);
    test::eq(mods[0], "shell");
    test::eq(mods[1], "git");
    test::eq(mods[2], "nvim");
    test::eq(mods[3], "vscode");
}

fn void test_resolve_extends_diamond_deduped() @test
{
    // development extends both base and desktop-common, which both
    // extend shared-shell — shared-shell's modules must appear once.
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("shared-shell", {}, { "shell" }));
    reg.add(mk_env("base", { "shared-shell" }, { "git" }));
    reg.add(mk_env("desktop-common", { "shared-shell" }, { "hyprland" }));
    reg.add(mk_env("development", { "base", "desktop-common" }, { "nvim" }));

    List{String} errors;
    errors.tinit();
    List{String} mods = resolve_extends_modules(&reg, "development", &errors);
    test::eq(errors.len(), 0);
    test::eq(mods.len(), 4); // shell, git, hyprland, nvim — not shell twice
    test::eq(mods[0], "shell");
}

fn void test_resolve_extends_unknown_target() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("development", { "ghost" }));

    List{String} errors;
    errors.tinit();
    resolve_extends_modules(&reg, "development", &errors);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("unknown environment"), "got: %s", errors[0]);
}

fn void test_resolve_extends_cycle() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("a", { "b" }));
    reg.add(mk_env("b", { "a" }));

    List{String} errors;
    errors.tinit();
    resolve_extends_modules(&reg, "a", &errors);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("circular environment inheritance"), "got: %s", errors[0]);
}

fn void test_validate_extends_refs_whole_registry() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("a", { "ghost1" }));
    reg.add(mk_env("b", { "ghost2" }));

    List{String} errors = validate_extends_refs(&reg);
    // both dangling refs reported, not just the first — permissive,
    // whole-registry-in-one-pass, unlike resolve_extends_modules which
    // only walks the one environment it was asked to resolve.
    test::eq(errors.len(), 2);
}

fn void test_validate_enable_refs() @test
{
    EnvironmentRegistry reg = environment_registry_init();
    reg.add(mk_env("base", {}, { "shell", "ghost" }));
    ModuleRegistry modules = module_registry_init();
    modules.add(mk("shell"));

    List{String} errors = validate_enable_refs(&reg, &modules);
    test::eq(errors.len(), 1);
    test::@check(errors[0].contains("ghost"), "got: %s", errors[0]);
}
