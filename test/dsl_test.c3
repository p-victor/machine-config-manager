module machine_config_manager::dsl;
import std::io;

fn void test_module_minimal() @test
{
    // Everything optional: id comes from the directory name, name
    // defaults to id, no restrictions.
    ModuleParse p = parse_module("", "shell");
    test::eq(p.errors.len(), 0);
    test::eq(p.decl.id, "shell");
    test::eq(p.decl.name, "shell");
    test::eq(p.decl.supports_distribution.len(), 0);
}

fn void test_module_full() @test
{
    String src = string::tformat(
        "# modules/nvim/module.mcm\n"
        "NAME Neovim\n"
        "DESCRIPTION Neovim editor configuration\n"
        "\n"
        "SUPPORTS arch ubuntu debian\n"
        "REQUIRES shell\n"
        "LINK .config/nvim\n"
    );
    ModuleParse p = parse_module(src, "nvim");
    test::eq(p.errors.len(), 0);
    test::eq(p.decl.id, "nvim");
    test::eq(p.decl.name, "Neovim");
    test::eq(p.decl.description, "Neovim editor configuration");
    test::eq(p.decl.supports_distribution.len(), 3);
    test::eq(p.decl.supports_distribution[0], "arch");
    test::eq(p.decl.supports_distribution[2], "debian");
    test::eq(p.decl.requires.len(), 1);
    test::eq(p.decl.requires[0], "shell");
    test::eq(p.decl.link.len(), 1);
    test::eq(p.decl.link[0], ".config/nvim");
}

fn void test_module_from() @test
{
    String src = "FROM base\nDESCRIPTION VS Code\n";
    ModuleParse p = parse_module(src, "vscode");
    test::eq(p.errors.len(), 0);
    test::eq(p.decl.from_module, "base");
}

fn void test_module_duplicate_from() @test
{
    String src = "FROM base\nFROM other\n";
    ModuleParse p = parse_module(src, "vscode");
    test::eq(p.errors.len(), 1);
}

fn void test_module_id_mismatch() @test
{
    String src = "ID wrong\n";
    ModuleParse p = parse_module(src, "shell");
    test::eq(p.errors.len(), 1);
    test::@check(p.errors[0].contains("does not match"), "expected a mismatch error, got: %s", p.errors[0]);
}

fn void test_module_id_explicit_ok() @test
{
    String src = "ID shell\nNAME Shell\n";
    ModuleParse p = parse_module(src, "shell");
    test::eq(p.errors.len(), 0);
    test::eq(p.decl.id, "shell");
}

fn void test_module_unknown_keyword() @test
{
    String src = "BOGUS foo\n";
    ModuleParse p = parse_module(src, "shell");
    test::eq(p.errors.len(), 1);
    test::@check(p.errors[0].contains("unknown keyword"), "expected an unknown-keyword error, got: %s", p.errors[0]);
}

fn void test_module_invalid_id() @test
{
    // Directory name itself is invalid (e.g. contains uppercase) — still
    // reported, even with no explicit ID line.
    ModuleParse p = parse_module("", "Not_Valid!");
    test::eq(p.errors.len(), 1);
}

fn void test_environment_full() @test
{
    String src = string::tformat(
        "# environments/development.mcm\n"
        "NAME Development\n"
        "DESCRIPTION Git, Neovim, VS Code and development tools\n"
        "ORDER 10\n"
        "\n"
        "SUPPORTS_DISTRO arch ubuntu debian\n"
        "SUPPORTS_CONTEXT native wsl\n"
        "SUPPORTS_ARCH x86_64 aarch64\n"
        "\n"
        "EXTENDS base\n"
        "\n"
        "ENABLE git shell nvim vscode\n"
        "\n"
        "REQUIRE_LOCAL GIT_NAME GIT_EMAIL\n"
        "DEFAULT_LOCAL EDITOR nvim\n"
        "DEFAULT_LOCAL PROJECTS_DIR $HOME/Workspace\n"
    );
    EnvironmentParse p = parse_environment(src, "development");
    test::eq(p.errors.len(), 0);
    test::eq(p.decl.id, "development");
    test::eq(p.decl.order, 10);
    test::eq(p.decl.supports_distribution.len(), 3);
    test::eq(p.decl.supports_context.len(), 2);
    test::eq(p.decl.supports_architecture.len(), 2);
    test::eq(p.decl.extends.len(), 1);
    test::eq(p.decl.extends[0], "base");
    test::eq(p.decl.enable.len(), 4);
    test::eq(p.decl.enable[3], "vscode");
    test::eq(p.decl.require_local.len(), 2);
    test::eq(p.decl.default_local.len(), 2);
    test::eq(p.decl.default_local[0].name, "EDITOR");
    test::eq(p.decl.default_local[0].value, "nvim");
    test::eq(p.decl.default_local[1].value, "$HOME/Workspace");
}

fn void test_environment_base_hidden() @test
{
    // Translated from machine-config's template/environments/base.sh
    String src = string::tformat(
        "NAME Base\n"
        "DESCRIPTION Shell configuration shared by every environment\n"
        "HIDDEN\n"
        "\n"
        "ENABLE shell git\n"
        "\n"
        "REQUIRE_LOCAL GIT_NAME GIT_EMAIL\n"
    );
    EnvironmentParse p = parse_environment(src, "base");
    test::eq(p.errors.len(), 0);
    test::eq(p.decl.hidden, true);
    test::eq(p.decl.deprecated, false);
    test::eq(p.decl.enable.len(), 2);
}

fn void test_environment_duplicate_enable() @test
{
    String src = "ENABLE git git\n";
    EnvironmentParse p = parse_environment(src, "x");
    test::eq(p.errors.len(), 1);
    test::@check(p.errors[0].contains("duplicate ENABLE"), "expected a duplicate-ENABLE error, got: %s", p.errors[0]);
}

fn void test_environment_bad_order() @test
{
    String src = "ORDER not-a-number\n";
    EnvironmentParse p = parse_environment(src, "x");
    test::eq(p.errors.len(), 1);
    test::eq(p.decl.order, 100); // default untouched
}

fn void test_environment_bad_default_local() @test
{
    String src = "DEFAULT_LOCAL ONLYNAME\n";
    EnvironmentParse p = parse_environment(src, "x");
    test::eq(p.errors.len(), 1);
}
