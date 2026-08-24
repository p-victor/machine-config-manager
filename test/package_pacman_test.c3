module machine_config_manager::package_pacman;
import std::io;
import std::os::process;

<*
 Read-only checks against the real pacman database — safe (no
 install/sync test exists anywhere in this project; those mutate the
 real system and are never exercised automatically). Both tests below
 no-op on a host with no pacman at all (e.g. the Ubuntu runner
 .github/workflows/release.yml's `test` job runs on — this project
 targets both distro families, but pacman itself is only ever real on
 one of them) rather than asserting anything: there is no portable "package
 guaranteed present" to check against pacman specifically once pacman
 itself isn't guaranteed present. Caught for real on a genuine Ubuntu CI
 run, not hypothetically — see the commit that added this comment.
*>
fn bool host_has_pacman()
{
    if (catch process::run({ "pacman", "--version" })) return false;
    return true;
}

fn void test_is_installed_true_for_pacman_itself() @test
{
    if (!host_has_pacman()) return;
    test::eq(is_installed("pacman"), true);
}

fn void test_is_installed_false_for_bogus_package() @test
{
    if (!host_has_pacman()) return;
    test::eq(is_installed("definitely-not-a-real-package-xyz-123"), false);
}
