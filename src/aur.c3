module machine_config_manager::aur;
import machine_config_manager::package_pacman;
import std::io;
import std::os::process;
import std::collections::list;

<*
 Never installs an AUR helper automatically — callers show
 bootstrap_instructions() to the user instead, a documented manual path,
 not an automatic one. AUR packages are community-maintained and not
 officially supported by Arch Linux; a caller planning an install is
 responsible for saying so before installing any.
*>
faultdef NO_AUR_HELPER;

fn bool runs(String cmd)
{
    if (catch process::run({ cmd, "--version" })) return false;
    return true;
}

<* "paru" or "yay", whichever is found first, or NO_AUR_HELPER. *>
fn String? detect_helper()
{
    if (runs("paru")) return "paru";
    if (runs("yay")) return "yay";
    return NO_AUR_HELPER~;
}

<* AUR packages register in pacman's local database like any other. *>
fn bool is_installed(String name) => package_pacman::is_installed(name);

<* Mutates the real system — never called from tests. *>
fn int? install(String[] names)
{
    String helper = detect_helper()!;
    if (names.len == 0) return 0;
    List{String} cmd;
    cmd.tinit();
    cmd.push(helper);
    cmd.push_all({ "-S", "--needed", "--noconfirm", "--" });
    cmd.push_all(names);
    return process::run(cmd.to_tarray(), process::SpawnOptions.INHERIT_STDIO);
}

fn String bootstrap_instructions() => `No AUR helper (paru or yay) was found. AUR packages are community
maintained and not officially reviewed by Arch Linux — read a package's
AUR page before installing it. To install paru:

    sudo pacman -S --needed base-devel git
    git clone https://aur.archlinux.org/paru.git
    cd paru && makepkg -si

Then re-run this command.
`;
