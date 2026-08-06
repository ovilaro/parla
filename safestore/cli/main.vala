namespace SafeStore {

    public class Cli : Object {

        private const string USAGE = """Usage: safestore [options] <command>

SafeStore always works on the Delta Chat accounts location: the plaintext
mount point is $DC_ACCOUNTS_PATH when set, otherwise the accounts path the
Parla JSON-RPC server will use, and the encrypted vault sits beside it as
"<accounts>.vault". Run "safestore status" to see the resolved paths.

Commands:
  check          Classify the accounts location: encrypted vault (exit 0),
                 decrypted vault mount (exit 3), or neither (exit 1)
  status         Show the resolved paths and the vault and mount state
  create         Create the encrypted vault and mount it
  mount          Unlock the encrypted vault onto the accounts path
  umount         Lock the mounted vault again
  forget         Remove the stored vault password from the keyring
  version        Show the CryFS backend version

Options:
  -b, --binary PATH       CryFS executable (default: settings or $SAFESTORE_CRYFS)
  -k, --keyring           Read the password from the system keyring; after a
                          successful interactive unlock, store it there
  -p, --password-stdin    Read the password from standard input (for scripts)
  -i, --idle MINUTES      Auto-lock after this many idle minutes
      --allow-exec        Allow direct execution of files inside the mount
  -q, --quiet             Print errors only
  -h, --help              Show this help

Passwords are never accepted on the command line and never written to disk
in plain text; the optional keyring entry lives in the OS secret service.
""";

        private Settings settings;
        private bool use_keyring = false;
        private bool password_stdin = false;
        private bool allow_executable_files = false;
        private bool quiet = false;
        private int idle_minutes = -1;

        public static int main (string[] args) {
            return new Cli ().run (args);
        }

        private int run (string[] args) {
            settings = new Settings ();

            string[] rest = {};
            for (int i = 1; i < args.length; i++) {
                string arg = args[i];
                switch (arg) {
                case "-h":
                case "--help":
                    stdout.printf ("%s", USAGE);
                    return 0;
                case "-k":
                case "--keyring":
                    use_keyring = true;
                    break;
                case "-p":
                case "--password-stdin":
                    password_stdin = true;
                    break;
                case "--allow-exec":
                    allow_executable_files = true;
                    break;
                case "-q":
                case "--quiet":
                    quiet = true;
                    break;
                case "-b":
                case "--binary":
                    if (++i >= args.length) return usage_error ("--binary needs a path");
                    settings.cryfs_binary = args[i];
                    break;
                case "-i":
                case "--idle":
                    if (++i >= args.length) return usage_error ("--idle needs a number of minutes");
                    idle_minutes = int.parse (args[i]);
                    if (idle_minutes < 0) return usage_error ("--idle must be zero or positive");
                    break;
                default:
                    if (arg.has_prefix ("-")) {
                        return usage_error ("Unknown option: " + arg);
                    }
                    rest += arg;
                    break;
                }
            }

            if (rest.length == 0) return usage_error ("Missing command");
            string command = rest[0];
            if (rest.length > 1) {
                return usage_error (
                    "Commands take no path arguments; the vault and mount "
                    + "locations follow DC_ACCOUNTS_PATH");
            }

            try {
                switch (command) {
                case "check":
                    return cmd_check ();
                case "status":
                    return cmd_status ();
                case "create":
                    return cmd_mount (true);
                case "mount":
                case "unlock":
                    return cmd_mount (false);
                case "umount":
                case "unmount":
                case "lock":
                    return cmd_umount ();
                case "forget":
                    return cmd_forget ();
                case "version":
                    stdout.printf ("%s\n",
                        Vault.backend_version (settings.cryfs_binary));
                    return 0;
                default:
                    return usage_error ("Unknown command: " + command);
                }
            } catch (Error error) {
                stderr.printf ("safestore: %s\n", error.message);
                if (error is VaultError.WRONG_PASSWORD && use_keyring) {
                    stderr.printf (
                        "The stored keyring password may be outdated; "
                        + "run \"safestore forget\" and retry.\n");
                }
                return 1;
            }
        }

        private int usage_error (string message) {
            stderr.printf ("safestore: %s\n%s", message, USAGE);
            return 2;
        }

        private void report (string message) {
            if (!quiet) stdout.printf ("%s\n", message);
        }

        private int cmd_check () {
            string vault = PathPolicy.normalize (settings.vault_path);
            string mount = PathPolicy.normalize (settings.mount_path);
            var info = Vault.mount_info (mount);
            if (info != null && info.is_cryfs ()) {
                string? source = info.vault_source ();
                report ("%s is a decrypted CryFS vault%s".printf (
                    mount,
                    source != null
                        ? " (encrypted at %s)".printf (source) : ""));
                return 3;
            }
            if (Vault.is_encrypted (vault)) {
                report ("%s is an encrypted CryFS vault".printf (vault));
                return 0;
            }
            if (info != null) {
                report ("%s is a mountpoint (%s), not a CryFS vault".printf (
                    mount, info.fstype.length > 0 ? info.fstype : "unknown"));
            } else {
                report ("%s is not an encrypted vault".printf (vault));
            }
            return 1;
        }

        private int cmd_status () {
            string vault = PathPolicy.normalize (settings.vault_path);
            string mount = PathPolicy.normalize (settings.mount_path);
            report ("accounts: %s (from %s)".printf (
                mount, AccountsPath.source ()));
            bool encrypted = Vault.is_encrypted (vault);
            report ("vault: %s (%s)".printf (
                vault, encrypted ? "encrypted vault" : "not a vault"));

            var info = Vault.mount_info (mount);
            if (info == null) {
                report ("mount: %s (not mounted)".printf (mount));
            } else if (info.is_cryfs ()) {
                string? source = info.vault_source ();
                report ("mount: %s (decrypted CryFS vault%s)".printf (
                    mount,
                    source != null ? ", encrypted at " + source : ""));
                if (source != null && source != vault) {
                    report ("warning: the mounted vault is not the "
                        + "configured one");
                }
            } else {
                report ("mount: %s (mounted, %s)".printf (
                    mount, info.fstype.length > 0 ? info.fstype : "unknown"));
            }
            return encrypted ? 0 : 1;
        }

        private int cmd_mount (bool create) throws Error {
            string vault = settings.vault_path;
            string mount = settings.mount_path;

            // Fail on a missing backend before bothering the user for a
            // password.
            Vault.resolve_binary (settings.cryfs_binary);

            bool from_keyring = false;
            string? password = null;
            if (!create && use_keyring) {
                if (!Keyring.available ()) {
                    stderr.printf (
                        "safestore: built without keyring support; "
                        + "falling back to a password prompt.\n");
                } else {
                    password = Keyring.lookup (vault);
                    from_keyring = password != null;
                }
            }
            if (password == null) {
                password = obtain_password (create);
                if (password == null) return 1;
            }

            Vault.mount (
                settings.cryfs_binary, vault, mount, password,
                create, idle_minutes > 0 ? idle_minutes : 0,
                allow_executable_files);
            report ((create ? "Vault created and mounted at %s"
                            : "Vault mounted at %s").printf (
                PathPolicy.normalize (mount)));

            if (use_keyring && !from_keyring && Keyring.available ()) {
                Keyring.store (vault, password);
                report ("Password stored in the system keyring.");
            }
            return 0;
        }

        private int cmd_umount () throws Error {
            string mount = settings.mount_path;
            Vault.unmount (settings.cryfs_binary, mount);
            report ("Vault locked; %s is no longer mounted.".printf (
                PathPolicy.normalize (mount)));
            return 0;
        }

        private int cmd_forget () throws Error {
            string vault = settings.vault_path;
            if (Keyring.forget (vault)) {
                report ("Stored password removed from the keyring.");
                return 0;
            }
            report ("No stored password found for this vault.");
            return 1;
        }

        private string? obtain_password (bool create) {
            if (password_stdin) {
                string? line = stdin.read_line ();
                return check_password (line, create);
            }

            string? password = prompt_password (
                create ? "New vault password" : "Vault password");
            password = check_password (password, create);
            if (password == null) return null;

            if (create) {
                string? repeated = prompt_password ("Confirm password");
                if (repeated != password) {
                    stderr.printf ("safestore: the passwords do not match.\n");
                    return null;
                }
            }
            return password;
        }

        private string? check_password (string? password, bool create) {
            if (password == null || password.length == 0) {
                stderr.printf ("safestore: the password cannot be empty.\n");
                return null;
            }
            if (password.contains ("\n") || password.contains ("\r")) {
                stderr.printf (
                    "safestore: passwords cannot contain line breaks.\n");
                return null;
            }
            if (create && password.char_count () < 12) {
                stderr.printf (
                    "safestore: use at least 12 characters for a new vault "
                    + "password.\n");
                return null;
            }
            return password;
        }

        private string? prompt_password (string label) {
#if WINDOWS
            stderr.printf ("%s: ", label);
            return stdin.read_line ();
#else
            if (!Posix.isatty (Posix.STDIN_FILENO)) {
                stderr.printf (
                    "safestore: no terminal available; use --password-stdin "
                    + "or --keyring.\n");
                return null;
            }
            stderr.printf ("%s: ", label);
            Posix.termios saved;
            bool hidden = Posix.tcgetattr (Posix.STDIN_FILENO, out saved) == 0;
            if (hidden) {
                Posix.termios silent = saved;
                silent.c_lflag &= ~Posix.ECHO;
                Posix.tcsetattr (Posix.STDIN_FILENO, Posix.TCSAFLUSH, silent);
            }
            string? line = stdin.read_line ();
            if (hidden) {
                Posix.tcsetattr (Posix.STDIN_FILENO, Posix.TCSAFLUSH, saved);
            }
            stderr.printf ("\n");
            return line;
#endif
        }
    }
}
