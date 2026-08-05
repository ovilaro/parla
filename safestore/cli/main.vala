namespace SafeStore {

    public class Cli : Object {

        private const string USAGE = """Usage: safestore [options] <command> [paths…]

Commands:
  check  [path]            Classify a folder: encrypted vault (exit 0),
                           decrypted vault mount (exit 3), or neither (exit 1)
  status [vault] [mount]   Show the vault and mount state
  create [vault] [mount]   Create a new encrypted vault and mount it
  mount  [vault] [mount]   Unlock an encrypted vault into the mount folder
  umount [mount]           Lock a mounted vault again
  forget [vault]           Remove a stored vault password from the keyring
  version                  Show the CryFS backend version

Options:
  -b, --binary PATH       CryFS executable (default: settings or $SAFESTORE_CRYFS)
  -k, --keyring           Read the password from the system keyring; after a
                          successful interactive unlock, store it there
  -p, --password-stdin    Read the password from standard input (for scripts)
  -i, --idle MINUTES      Auto-lock after this many idle minutes
  -q, --quiet             Print errors only
  -h, --help              Show this help

Omitted paths default to the SafeStore settings, shared with the GUI.
Passwords are never accepted on the command line and never written to disk
in plain text; the optional keyring entry lives in the OS secret service.
""";

        private Settings settings;
        private bool use_keyring = false;
        private bool password_stdin = false;
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
            string[] paths = rest[1:rest.length];

            try {
                switch (command) {
                case "check":
                    return cmd_check (paths);
                case "status":
                    return cmd_status (paths);
                case "create":
                    return cmd_mount (paths, true);
                case "mount":
                case "unlock":
                    return cmd_mount (paths, false);
                case "umount":
                case "unmount":
                case "lock":
                    return cmd_umount (paths);
                case "forget":
                    return cmd_forget (paths);
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

        private string vault_arg (string[] paths) {
            return paths.length > 0 ? paths[0] : settings.vault_path;
        }

        private string mount_arg (string[] paths, int index) {
            return paths.length > index ? paths[index] : settings.mount_path;
        }

        private void report (string message) {
            if (!quiet) stdout.printf ("%s\n", message);
        }

        private int cmd_check (string[] paths) {
            string path = PathPolicy.normalize (vault_arg (paths));
            var info = Vault.mount_info (path);
            if (info != null && info.is_cryfs ()) {
                string? source = info.vault_source ();
                report ("%s is a decrypted CryFS vault%s".printf (
                    path,
                    source != null
                        ? " (encrypted at %s)".printf (source) : ""));
                return 3;
            }
            if (Vault.is_encrypted (path)) {
                report ("%s is an encrypted CryFS vault".printf (path));
                return 0;
            }
            if (info != null) {
                report ("%s is a mountpoint (%s), not a CryFS vault".printf (
                    path, info.fstype.length > 0 ? info.fstype : "unknown"));
            } else {
                report ("%s is not an encrypted vault".printf (path));
            }
            return 1;
        }

        private int cmd_status (string[] paths) {
            string vault = PathPolicy.normalize (vault_arg (paths));
            string mount = PathPolicy.normalize (mount_arg (paths, 1));
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

        private int cmd_mount (string[] paths, bool create) throws Error {
            string vault = vault_arg (paths);
            string mount = mount_arg (paths, 1);

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
                create, idle_minutes > 0 ? idle_minutes : 0);
            report ((create ? "Vault created and mounted at %s"
                            : "Vault mounted at %s").printf (
                PathPolicy.normalize (mount)));

            if (use_keyring && !from_keyring && Keyring.available ()) {
                Keyring.store (vault, password);
                report ("Password stored in the system keyring.");
            }
            return 0;
        }

        private int cmd_umount (string[] paths) throws Error {
            string mount = paths.length > 0 ? paths[0] : settings.mount_path;
            Vault.unmount (settings.cryfs_binary, mount);
            report ("Vault locked; %s is no longer mounted.".printf (
                PathPolicy.normalize (mount)));
            return 0;
        }

        private int cmd_forget (string[] paths) throws Error {
            string vault = vault_arg (paths);
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
