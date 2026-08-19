module machine_config_manager::platform;
import std::io;

const String ARCH_OS_RELEASE = `NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
`;

const String ENDEAVOUR_OS_RELEASE = `NAME="EndeavourOS"
PRETTY_NAME="EndeavourOS"
ID="endeavouros"
ID_LIKE="arch"
`;

const String UBUNTU_OS_RELEASE = `NAME="Ubuntu"
PRETTY_NAME="Ubuntu 24.04 LTS"
ID=ubuntu
ID_LIKE=debian
`;

const String UNKNOWN_OS_RELEASE = `NAME="Some Distro"
PRETTY_NAME="Some Distro 1.0"
ID=solus
`;

fn void test_parse_os_release_field_found() @test
{
    String? v = parse_os_release_field(ARCH_OS_RELEASE, "ID");
    test::eq(v!!, "arch");
}

fn void test_parse_os_release_field_strips_quotes() @test
{
    String? v = parse_os_release_field(ENDEAVOUR_OS_RELEASE, "PRETTY_NAME");
    test::eq(v!!, "EndeavourOS");
}

fn void test_parse_os_release_field_missing() @test
{
    if (catch parse_os_release_field(ARCH_OS_RELEASE, "NOPE")) return;
    test::@check(false, "expected FIELD_NOT_FOUND");
}

fn void test_parse_distro_id_direct() @test
{
    test::eq(parse_distro_id(ARCH_OS_RELEASE), "arch");
    test::eq(parse_distro_id(ENDEAVOUR_OS_RELEASE), "endeavouros");
}

fn void test_parse_distro_id_unreadable_falls_back_unknown() @test
{
    test::eq(parse_distro_id(""), "unknown");
}

fn void test_parse_distro_family_direct_match() @test
{
    test::eq(parse_distro_family_with_fallback(ARCH_OS_RELEASE), "arch");
    test::eq(parse_distro_family_with_fallback(UBUNTU_OS_RELEASE), "debian");
}

fn void test_parse_distro_family_via_id_like() @test
{
    // "endeavouros" is itself in the direct-match list, so this also
    // covers the direct path — see the ID_LIKE-only case below for the
    // fallback path specifically.
    test::eq(parse_distro_family_with_fallback(ENDEAVOUR_OS_RELEASE), "arch");
}

fn void test_parse_distro_family_id_like_fallback_only() @test
{
    String content = `ID=arch-derivative-nobody-heard-of
ID_LIKE=arch
`;
    test::eq(parse_distro_family_with_fallback(content), "arch");
}

fn void test_parse_distro_family_unknown() @test
{
    test::eq(parse_distro_family_with_fallback(UNKNOWN_OS_RELEASE), "unknown");
}

fn void test_parse_pretty_name_falls_back_to_id() @test
{
    String content = "ID=arch\n";
    test::eq(parse_pretty_name(content), "arch");
}

fn void test_parse_arch_normalizes_aliases() @test
{
    test::eq(parse_arch("x86_64")!!, "x86_64");
    test::eq(parse_arch("amd64")!!, "x86_64");
    test::eq(parse_arch("aarch64")!!, "aarch64");
    test::eq(parse_arch("arm64")!!, "aarch64");
}

fn void test_parse_arch_unsupported() @test
{
    if (catch parse_arch("i686")) return;
    test::@check(false, "expected UNSUPPORTED_ARCH");
}

fn void test_parse_is_wsl_via_env() @test
{
    test::eq(parse_is_wsl("Ubuntu", "", ""), true);
    test::eq(parse_is_wsl("", "1", ""), true);
    test::eq(parse_is_wsl("", "", ""), false);
}

fn void test_parse_is_wsl_via_proc_version() @test
{
    test::eq(parse_is_wsl("", "", "Linux version 5.15.0 (Microsoft@WSL2)"), true);
    test::eq(parse_is_wsl("", "", "Linux version 6.1.0-arch1"), false);
}

fn void test_parse_wsl_version_not_wsl() @test
{
    test::eq(parse_wsl_version(false, "anything", false), 0);
}

fn void test_parse_wsl_version_2_via_content() @test
{
    test::eq(parse_wsl_version(true, "WSL2", false), 2);
}

fn void test_parse_wsl_version_2_via_marker() @test
{
    test::eq(parse_wsl_version(true, "", true), 2);
}

fn void test_parse_wsl_version_1() @test
{
    test::eq(parse_wsl_version(true, "", false), 1);
}
