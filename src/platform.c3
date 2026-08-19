module machine_config_manager::platform;
import std::io;
import std::io::file;
import std::io::path;
import std::os::process;
import std::os::env;

faultdef FIELD_NOT_FOUND, UNSUPPORTED_ARCH;

<*
 Detected platform facts — same fields lib/platform.sh's mc_platform_detect
 populates (MC_DISTRO_ID, MC_DISTRO_FAMILY, ...), just gathered once into a
 struct instead of global variables.
*>
struct Platform
{
    String distro_id;
    String distro_family; // "arch", "debian", or "unknown"
    String pretty_name;
    String arch;          // "x86_64" or "aarch64"
    bool is_wsl;
    int wsl_version;       // 0 when not WSL
    String context;        // "native" or "wsl"
    String username;
}

<*
 Every parse_* function below is pure (string/bool in, value out) so the
 detection logic is unit-testable without touching the real machine — same
 reason lib/platform.sh accepts *_OVERRIDE env vars, just via parameters
 instead. detect() at the bottom is the only part that actually reads
 /etc/os-release, runs `uname`, etc.
*>
fn String? parse_os_release_field(String content, String field)
{
    String[] lines = content.tsplit("\n");
    foreach (line : lines)
    {
        sz? eq = line.index_of_char('=');
        if (catch eq) continue;
        String key = line[0..eq - 1];
        if (key != field) continue;
        String value = line[eq + 1..];
        value = value.strip_prefix("\"");
        value = value.strip_suffix("\"");
        return value;
    }
    return FIELD_NOT_FOUND~;
}

fn String parse_distro_id(String os_release_content)
{
    String? id = parse_os_release_field(os_release_content, "ID");
    if (catch id) return "unknown";
    return id.to_lower_tcopy();
}

fn String parse_distro_family(String distro_id)
{
    switch (distro_id)
    {
        case "arch":
        case "archlinux":
        case "manjaro":
        case "endeavouros":
        case "artix":
            return "arch";
        case "ubuntu":
        case "debian":
        case "linuxmint":
        case "pop":
        case "raspbian":
            return "debian";
        default:
            break;
    }
    return "unknown";
}

fn String parse_distro_family_with_fallback(String os_release_content)
{
    String id = parse_distro_id(os_release_content);
    String family = parse_distro_family(id);
    if (family != "unknown") return family;

    String? id_like = parse_os_release_field(os_release_content, "ID_LIKE");
    if (catch id_like) return "unknown";
    String lowered = id_like.to_lower_tcopy();
    if (lowered.contains("arch")) return "arch";
    if (lowered.contains("debian") || lowered.contains("ubuntu")) return "debian";
    return "unknown";
}

fn String parse_pretty_name(String os_release_content)
{
    String? pretty = parse_os_release_field(os_release_content, "PRETTY_NAME");
    if (catch pretty) return parse_distro_id(os_release_content);
    return pretty;
}

fn String? parse_arch(String uname_m_output)
{
    String machine = uname_m_output.trim();
    switch (machine)
    {
        case "x86_64":
        case "amd64":
            return "x86_64";
        case "aarch64":
        case "arm64":
            return "aarch64";
        default:
            return UNSUPPORTED_ARCH~;
    }
}

fn bool parse_is_wsl(String wsl_distro_name_env, String wsl_interop_env, String proc_version_content)
{
    if (wsl_distro_name_env.len > 0) return true;
    if (wsl_interop_env.len > 0) return true;
    return proc_version_content.to_lower_tcopy().contains("microsoft");
}

fn int parse_wsl_version(bool is_wsl, String proc_version_content, bool wsl_marker_exists)
{
    if (!is_wsl) return 0;
    if (proc_version_content.contains("WSL2") || wsl_marker_exists) return 2;
    return 1;
}

<*
 Reads /etc/os-release, runs `uname -m`, checks WSL env vars/markers, and
 assembles a Platform. Dies (returns UNSUPPORTED_ARCH) only on an
 architecture machine-config-manager doesn't support — everything else
 degrades to "unknown" rather than failing, same as mc_platform_detect.
*>
fn Platform? detect()
{
    char[]? os_release_raw = file::load_temp("/etc/os-release");
    String os_release_content = "";
    if (try raw = os_release_raw) os_release_content = (String)raw;

    char[512] uname_buf;
    String? uname_out = process::run_capture_stdout(&uname_buf, { "uname", "-m" });
    String arch = "";
    if (try out = uname_out) arch = parse_arch(out)!;

    char[] proc_version_raw = file::load_temp("/proc/version") ?? (char[]){};
    String proc_version_content = (String)proc_version_raw;

    String wsl_distro_env = env::tget_var("WSL_DISTRO_NAME") ?? "";
    String wsl_interop_env = env::tget_var("WSL_INTEROP") ?? "";
    bool is_wsl = parse_is_wsl(wsl_distro_env, wsl_interop_env, proc_version_content);
    bool wsl_marker = path::exists(path::tnew("/run/WSL") ?? (Path)"");
    int wsl_version = parse_wsl_version(is_wsl, proc_version_content, wsl_marker);

    String username = env::tget_var("USER") ?? "unknown";

    return {
        .distro_id = parse_distro_id(os_release_content),
        .distro_family = parse_distro_family_with_fallback(os_release_content),
        .pretty_name = parse_pretty_name(os_release_content),
        .arch = arch,
        .is_wsl = is_wsl,
        .wsl_version = wsl_version,
        .context = is_wsl ? "wsl" : "native",
        .username = username,
    };
}
