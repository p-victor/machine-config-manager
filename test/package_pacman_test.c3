module machine_config_manager::package_pacman;
import std::io;

<*
 Read-only checks against the real pacman database — safe (no
 install/sync test exists anywhere in this project; those mutate the
 real system and are never exercised automatically). "pacman" itself is
 guaranteed present on any machine these tests run on.
*>
fn void test_is_installed_true_for_pacman_itself() @test
{
    test::eq(is_installed("pacman"), true);
}

fn void test_is_installed_false_for_bogus_package() @test
{
    test::eq(is_installed("definitely-not-a-real-package-xyz-123"), false);
}
