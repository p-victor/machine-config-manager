module machine_config_manager::env_select;
import machine_config_manager::registry;
import machine_config_manager::dsl;
import std::io;
import std::collections::list;

fn dsl::EnvironmentDecl mk_env(String id, int order = 100, bool hidden = false, String[] distros = {}, String[] contexts = {}, String[] arches = {})
{
    dsl::EnvironmentDecl e = dsl::environment_decl_init();
    e.id = id;
    e.name = id;
    e.order = order;
    e.hidden = hidden;
    e.supports_distribution.push_all(distros);
    e.supports_context.push_all(contexts);
    e.supports_architecture.push_all(arches);
    return e;
}

fn void test_list_allows_empty_is_unrestricted() @test
{
    List{String} empty;
    empty.tinit();
    test::eq(list_allows(&empty, "anything"), true);
}

fn void test_list_allows_checks_membership() @test
{
    List{String} l;
    l.tinit();
    l.push_all({ "arch", "ubuntu" });
    test::eq(list_allows(&l, "arch"), true);
    test::eq(list_allows(&l, "debian"), false);
}

fn void test_is_compatible_all_dimensions() @test
{
    dsl::EnvironmentDecl e = mk_env("dev", 100, false, { "arch" }, { "native" }, { "x86_64" });
    test::eq(is_compatible(&e, "arch", "native", "x86_64"), true);
    test::eq(is_compatible(&e, "ubuntu", "native", "x86_64"), false);
    test::eq(is_compatible(&e, "arch", "wsl", "x86_64"), false);
    test::eq(is_compatible(&e, "arch", "native", "aarch64"), false);
}

fn void test_is_compatible_unrestricted_matches_everything() @test
{
    dsl::EnvironmentDecl e = mk_env("dev");
    test::eq(is_compatible(&e, "arch", "native", "x86_64"), true);
    test::eq(is_compatible(&e, "ubuntu", "wsl", "aarch64"), true);
}

fn void test_compatible_ids_excludes_hidden() @test
{
    registry::EnvironmentRegistry reg = registry::environment_registry_init();
    reg.add(mk_env("base", 100, true));
    reg.add(mk_env("dev", 100, false));

    List{String} ids = compatible_ids(&reg, "arch", "native", "x86_64");
    test::eq(ids.len(), 1);
    test::eq(ids[0], "dev");
}

fn void test_compatible_ids_excludes_incompatible_platform() @test
{
    registry::EnvironmentRegistry reg = registry::environment_registry_init();
    reg.add(mk_env("linux-only", 100, false, { "arch" }));
    reg.add(mk_env("any", 100, false));

    List{String} ids = compatible_ids(&reg, "ubuntu", "native", "x86_64");
    test::eq(ids.len(), 1);
    test::eq(ids[0], "any");
}

fn void test_compatible_ids_sorted_by_order() @test
{
    registry::EnvironmentRegistry reg = registry::environment_registry_init();
    reg.add(mk_env("c", 30));
    reg.add(mk_env("a", 10));
    reg.add(mk_env("b", 20));

    List{String} ids = compatible_ids(&reg, "arch", "native", "x86_64");
    test::eq(ids.len(), 3);
    test::eq(ids[0], "a");
    test::eq(ids[1], "b");
    test::eq(ids[2], "c");
}

fn void test_compatible_ids_ties_keep_discovery_order() @test
{
    // Same order value — stable sort preserves the order they were added
    // in (discovery/directory-listing order), not an alphabetical
    // secondary sort by id.
    registry::EnvironmentRegistry reg = registry::environment_registry_init();
    reg.add(mk_env("zebra", 50));
    reg.add(mk_env("apple", 50));

    List{String} ids = compatible_ids(&reg, "arch", "native", "x86_64");
    test::eq(ids.len(), 2);
    test::eq(ids[0], "zebra");
    test::eq(ids[1], "apple");
}

fn void test_compatible_ids_empty_when_nothing_matches() @test
{
    registry::EnvironmentRegistry reg = registry::environment_registry_init();
    reg.add(mk_env("hidden-one", 100, true));

    List{String} ids = compatible_ids(&reg, "arch", "native", "x86_64");
    test::eq(ids.len(), 0);
}
