module machine_config_manager::prompt;
import std::io;

<*
 Prompts for a line of input, trimmed. Returns a fault if stdin is closed/
 unreadable (piped from /dev/null, a non-interactive CI run) rather than
 hanging — callers decide what that means for them (usually: die with a
 clear message, same as lib/prompt.sh's mc_prompt_guard).
*>
fn String? input(String question)
{
    io::printf("%s: ", question);
    (void)io::stdout().flush();
    String line = io::treadline()!;
    return line.trim().tcopy();
}

<*
 y/n prompt with a default taken on a bare Enter. A closed/unreadable
 stdin falls back to the default rather than failing — confirmations are
 lower-stakes than input() (there's always a sensible way to interpret
 "no answer given").
*>
fn bool confirm(String question, bool default_yes)
{
    String suffix = default_yes ? "[Y/n]" : "[y/N]";
    io::printf("%s %s: ", question, suffix);
    (void)io::stdout().flush();
    String? line = io::treadline();
    if (catch line) return default_yes;
    String trimmed = line.trim().to_lower_tcopy();
    if (trimmed.len == 0) return default_yes;
    return trimmed == "y" || trimmed == "yes";
}
