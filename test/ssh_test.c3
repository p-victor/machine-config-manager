module machine_config_manager::ssh;
import std::io;
import std::io::path;
import std::io::file;

fn String workspace(String name)
{
    String dir = string::tformat("/tmp/mcm-ssh-test-%s", name);
    (void)path::rmtree(path::tnew(dir)!!);
    (void)path::mkdir(dir, true);
    return dir;
}

fn void test_find_existing_key_none() @test
{
    String dir = workspace("none");
    if (catch find_existing_key(dir)) return; // expected
    test::@check(false, "expected NO_KEY_FOUND");
}

fn void test_find_existing_key_requires_pub_pair() @test
{
    // A private key with no matching .pub doesn't count.
    String dir = workspace("no-pub");
    file::save(string::tformat("%s/id_ed25519", dir), "fake private key")!!;
    if (catch find_existing_key(dir)) return; // expected
    test::@check(false, "expected NO_KEY_FOUND (missing .pub)");
}

fn void test_find_existing_key_found() @test
{
    String dir = workspace("found");
    file::save(string::tformat("%s/id_ed25519", dir), "fake private key")!!;
    file::save(string::tformat("%s/id_ed25519.pub", dir), "fake public key")!!;

    String found = find_existing_key(dir)!!;
    test::eq(found, string::tformat("%s/id_ed25519", dir));
}

fn void test_find_existing_key_prefers_ed25519_over_rsa() @test
{
    String dir = workspace("prefers-ed25519");
    file::save(string::tformat("%s/id_rsa", dir), "x")!!;
    file::save(string::tformat("%s/id_rsa.pub", dir), "x")!!;
    file::save(string::tformat("%s/id_ed25519", dir), "x")!!;
    file::save(string::tformat("%s/id_ed25519.pub", dir), "x")!!;

    String found = find_existing_key(dir)!!;
    test::eq(found, string::tformat("%s/id_ed25519", dir));
}

fn void test_public_key_path() @test
{
    test::eq(public_key_path("/home/user/.ssh/id_ed25519"), "/home/user/.ssh/id_ed25519.pub");
}

fn void test_show_public_key() @test
{
    String dir = workspace("show-pub");
    String priv = string::tformat("%s/id_ed25519", dir);
    file::save(string::tformat("%s.pub", priv), "ssh-ed25519 AAAA... comment\n")!!;

    String pub = show_public_key(priv)!!;
    test::eq(pub, "ssh-ed25519 AAAA... comment\n");
}

fn void test_show_public_key_missing_fails() @test
{
    String dir = workspace("show-pub-missing");
    if (catch show_public_key(string::tformat("%s/id_ed25519", dir))) return; // expected
    test::@check(false, "expected a failure reading a nonexistent .pub");
}
