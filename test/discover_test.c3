module machine_config_manager::discover;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import std::io;
import std::collections::list;

const String FIXTURE_ROOT = "test/fixtures/sample_config";

fn void test_discover_modules() @test
{
    ModuleDiscovery d = discover_modules(FIXTURE_ROOT);

    // "broken"'s BOGUS line reports one error but doesn't stop it from
    // being registered — permissive discovery, same as every other layer.
    test::eq(d.modules.modules.len(), 3);
    test::eq(d.errors.len(), 1);
    test::@check(d.errors[0].contains("broken/module.mcm"), "got: %s", d.errors[0]);
    test::@check(d.errors[0].contains("unknown keyword"), "got: %s", d.errors[0]);

    dsl::ModuleDecl* shell = d.modules.find("shell")!!;
    test::eq(shell.description, "Interactive shell configuration (prompt, aliases, environment)");
    test::eq(shell.supports_distribution.len(), 3);

    dsl::ModuleDecl* nvim = d.modules.find("nvim")!!;
    test::eq(nvim.name, "Neovim");
    test::eq(nvim.requires.len(), 1);
    test::eq(nvim.requires[0], "shell");
    test::eq(nvim.link.len(), 1);
    test::eq(nvim.link[0], ".config/nvim");
}

fn void test_discover_modules_missing_dir_is_empty_not_error() @test
{
    ModuleDiscovery d = discover_modules("test/fixtures/does-not-exist");
    test::eq(d.modules.modules.len(), 0);
    test::eq(d.errors.len(), 0);
}

fn void test_discover_environments() @test
{
    EnvironmentDiscovery d = discover_environments(FIXTURE_ROOT);

    test::eq(d.environments.environments.len(), 2);
    test::eq(d.errors.len(), 0);

    dsl::EnvironmentDecl* base = d.environments.find("base")!!;
    test::eq(base.hidden, true);
    test::eq(base.enable.len(), 1);
    test::eq(base.enable[0], "shell");

    dsl::EnvironmentDecl* dev = d.environments.find("development")!!;
    test::eq(dev.order, 10);
    test::eq(dev.extends.len(), 1);
    test::eq(dev.extends[0], "base");
}

fn void test_discover_full_pipeline_resolves_end_to_end() @test
{
    // Ties discovery straight into the pure registry-resolution layer:
    // "development" EXTENDS "base" (ENABLE shell) and ENABLEs nvim, which
    // REQUIRES shell — the resolved module set should be exactly
    // {shell, nvim}, deduped, dependency-then-self order.
    ModuleDiscovery md = discover_modules(FIXTURE_ROOT);
    EnvironmentDiscovery ed = discover_environments(FIXTURE_ROOT);

    List{String} errors;
    errors.tinit();
    List{String} enabled = registry::resolve_extends_modules(&ed.environments, "development", &errors);
    test::eq(errors.len(), 0);
    test::eq(enabled.len(), 2);
    test::eq(enabled[0], "shell");
    test::eq(enabled[1], "nvim");

    List{String} req_errors;
    req_errors.tinit();
    List{String} resolved = registry::expand_requires(&md.modules, enabled.to_tarray(), &req_errors);
    test::eq(req_errors.len(), 0);
    test::eq(resolved.len(), 2);
    test::eq(resolved[0], "shell");
    test::eq(resolved[1], "nvim");
}
