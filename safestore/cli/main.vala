namespace SafeStore {

    public class Cli : Object {

        private const string USAGE = """Usage: safestore [options] <command>

SafeStore always works on the Delta Chat accounts location: the plaintext
path is $DC_ACCOUNTS_PATH when set, otherwise the accounts path the Parla
JSON-RPC server will use. CryFS stores "<accounts>.vault"; ZIP stores
"<accounts>.zip". Run "safestore status" to see the resolved paths.

Commands:
  backends       List encryption backends, availability, and security model
  check          Classify the accounts location: encrypted vault (exit 0),
                 unlocked plaintext view (exit 3), or neither (exit 1)
  status         Show the resolved paths and the vault and mount state
  create         Create and unlock the selected encrypted store
  mount          Unlock the selected store onto the accounts path
  umount         Lock the selected store again
  forget         Remove the stored vault password from the keyring
  version        Show status for the selected encryption backend

Options:
      --backend NAME      Select cryfs or zip (and save the selection)
  -b, --binary PATH       Main executable for the selected backend
      --unzip-binary PATH unzip executable for the ZIP backend
      --shred              Best-effort overwrite of ZIP plaintext before removal
      --shred-binary PATH shred-compatible executable
  -k, --keyring           Read the password from the system keyring; after a
                          successful interactive unlock, store it there
  -p, --password-stdin    Read the password from standard input (for scripts)
  -i, --idle MINUTES      CryFS: auto-lock after this many idle minutes
      --allow-exec        CryFS: allow direct execution inside the mount
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
        private string? binary_override = null;

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
                    binary_override = args[i];
                    break;
                case "--backend":
                    if (++i >= args.length) return usage_error ("--backend needs a name");
                    try {
                        Backends.select (settings, BackendKind.parse (args[i]));
                    } catch (Error error) {
                        return usage_error (error.message);
                    }
                    settings.save ();
                    break;
                case "--unzip-binary":
                    if (++i >= args.length) return usage_error ("--unzip-binary needs a path");
                    settings.unzip_binary = args[i];
                    break;
                case "--shred":
                    settings.secure_delete = true;
                    break;
                case "--shred-binary":
                    if (++i >= args.length) return usage_error ("--shred-binary needs a path");
                    settings.shred_binary = args[i];
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
            if (binary_override != null) {
                if (settings.backend == "zip") {
                    settings.zip_binary = binary_override;
                } else {
                    settings.cryfs_binary = binary_override;
                }
            }
            string command = rest[0];
            if (rest.length > 1) {
                return usage_error (
                    "Commands take no path arguments; the vault and mount "
                    + "locations follow DC_ACCOUNTS_PATH");
            }

            try {
                switch (command) {
                case "backends":
                case "list-backends":
                    return cmd_backends ();
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
                    return cmd_version ();
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
            if (settings.backend == "zip") {
                if (ZipBackend.is_encrypted (settings)) {
                    bool unlocked = ZipBackend.is_unlocked (settings);
                    report (unlocked
                        ? "%s is a SafeStore ZIP vault with plaintext exposed at %s".printf (
                            AccountsPath.zip_path (), settings.mount_path)
                        : "%s is a locked SafeStore ZIP vault".printf (
                            AccountsPath.zip_path ()));
                    return unlocked ? 3 : 0;
                }
                report ("%s is not a SafeStore ZIP vault".printf (
                    AccountsPath.zip_path ()));
                return 1;
            }
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

        private int cmd_status () throws Error {
            BackendInfo selected = Backends.selected (settings);
            report ("backend: %s (%s)".printf (
                selected.name, selected.available ? "available" : "unavailable"));
            report ("backend status: " + selected.status);
            string vault = PathPolicy.normalize (settings.vault_path);
            string mount = PathPolicy.normalize (settings.mount_path);
            report ("accounts: %s (from %s)".printf (
                mount, AccountsPath.source ()));
            bool encrypted = settings.backend == "zip"
                ? ZipBackend.is_encrypted (settings) : Vault.is_encrypted (vault);
            report ("vault: %s (%s)".printf (
                vault, encrypted ? "encrypted vault" : "not a vault"));

            if (settings.backend == "zip") {
                bool locked = encrypted
                    && !ZipBackend.is_unlocked (settings);
                report ("plaintext: %s (%s)".printf (
                    mount, locked ? "locked placeholder only"
                        : (encrypted ? "extracted while unlocked"
                                     : "not managed by a ZIP vault")));
                EraseInfo erase = PlaintextEraser.inspect (settings);
                report ("overwrite removal: %s%s".printf (
                    erase.status,
                    settings.secure_delete ? "; selected" : "; not selected"));
                return encrypted ? 0 : 1;
            }

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
            BackendInfo backend = Backends.selected (settings);
            if (!backend.available) {
                throw new VaultError.BACKEND ("%s", backend.status);
            }

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
                password = obtain_password (create, create);
                if (password == null) return 1;
            }

            var secret = new SecretValue (password);
            password = "";

            try {
                if (settings.backend == "zip") {
                    if (create) EncryptedStore.create (settings, secret.peek ());
                    else EncryptedStore.unlock (settings, secret.peek ());
                } else {
                    if (idle_minutes >= 0) settings.idle_minutes = idle_minutes;
                    if (create) {
                        EncryptedStore.create (
                            settings, secret.peek (), allow_executable_files);
                    } else {
                        EncryptedStore.unlock (
                            settings, secret.peek (), allow_executable_files);
                    }
                }
                report ((create ? "Vault created and unlocked at %s"
                                : "Vault unlocked at %s").printf (
                    PathPolicy.normalize (mount)));

                if (use_keyring && !from_keyring && Keyring.available ()) {
                    Keyring.store (vault, secret.peek ());
                    report ("Password stored in the system keyring.");
                }
            } finally {
                secret.clear ();
            }
            return 0;
        }

        private int cmd_umount () throws Error {
            string mount = settings.mount_path;
            if (settings.backend == "zip") {
                string? password = use_keyring
                    ? Keyring.lookup (settings.vault_path) : null;
                // ZIP locking rewrites and re-encrypts the archive, so an
                // interactive password must be entered twice to avoid making
                // a typo the new (and only) vault password.
                if (password == null) password = obtain_password (true, false);
                if (password == null) return 1;
                var secret = new SecretValue (password);
                password = "";
                try {
                    EncryptedStore.lock (settings, secret.peek ());
                } finally {
                    secret.clear ();
                }
                report ("ZIP vault locked; plaintext accounts were removed.");
            } else {
                EncryptedStore.lock (settings);
                report ("Vault locked; %s is no longer mounted.".printf (
                    PathPolicy.normalize (mount)));
            }
            return 0;
        }

        private int cmd_backends () {
            foreach (BackendInfo info in Backends.list (settings)) {
                report ("%s%s — %s".printf (
                    info.id,
                    info.id == settings.backend ? " (selected)" : "",
                    info.available ? "available" : "unavailable"));
                report ("  %s".printf (info.status));
                report ("  Protection: %s".printf (info.protection));
                report ("  Operation: %s".printf (info.operation));
                report ("  Vault: %s".printf (info.vault_path));
            }
            EraseInfo erase = PlaintextEraser.inspect (settings);
            report ("shred — %s".printf (erase.status));
            report ("  Warning: %s".printf (erase.warning));
            return 0;
        }

        private int cmd_version () throws Error {
            BackendInfo info = Backends.selected (settings);
            stdout.printf ("%s: %s\n", info.name, info.status);
            return info.available ? 0 : 1;
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

        private string? obtain_password (bool confirm,
                                         bool new_password) {
            if (password_stdin) {
                string? line = stdin.read_line ();
                return check_password (line, new_password);
            }

            string? password = prompt_password (
                new_password ? "New vault password" : "Vault password");
            password = check_password (password, new_password);
            if (password == null) return null;

            if (confirm) {
                string? repeated = prompt_password ("Confirm password");
                if (repeated != password) {
                    stderr.printf ("safestore: the passwords do not match.\n");
                    return null;
                }
            }
            return password;
        }

        private string? check_password (string? password,
                                        bool new_password) {
            if (password == null || password.length == 0) {
                stderr.printf ("safestore: the password cannot be empty.\n");
                return null;
            }
            if (password.contains ("\n") || password.contains ("\r")) {
                stderr.printf (
                    "safestore: passwords cannot contain line breaks.\n");
                return null;
            }
            if (settings.backend == "zip") {
                for (int i = 0; i < password.length; i++) {
                    uint8 byte = password.data[i];
                    if (byte < 0x20 || byte == 0x7f) {
                        stderr.printf (
                            "safestore: ZIP passwords cannot contain control characters.\n");
                        return null;
                    }
                }
            }
            if (new_password && password.char_count () < 12) {
                stderr.printf (
                    "safestore: use at least 12 characters for a new vault "
                    + "password.\n");
                return null;
            }
            return password;
        }

        private string? prompt_password (string label) {
#if WINDOWS
            stderr.printf (
                "safestore: secure interactive password input is not "
                + "available on this platform; use --password-stdin "
                + "or --keyring.\n");
            return null;
#else
            if (!Posix.isatty (Posix.STDIN_FILENO)) {
                stderr.printf (
                    "safestore: no terminal available; use --password-stdin "
                    + "or --keyring.\n");
                return null;
            }
            stderr.printf ("%s: ", label);
            Posix.termios saved;
            if (Posix.tcgetattr (Posix.STDIN_FILENO, out saved) != 0) {
                stderr.printf (
                    "safestore: cannot read terminal settings; refusing "
                    + "an unsafe password prompt.\n");
                return null;
            }
            Posix.termios silent = saved;
            silent.c_lflag &= ~Posix.ECHO;
            if (Posix.tcsetattr (
                    Posix.STDIN_FILENO, Posix.TCSAFLUSH, silent) != 0) {
                stderr.printf (
                    "safestore: cannot disable terminal echo; refusing "
                    + "an unsafe password prompt.\n");
                return null;
            }
            string? line = stdin.read_line ();
            if (Posix.tcsetattr (
                    Posix.STDIN_FILENO, Posix.TCSAFLUSH, saved) != 0) {
                stderr.printf (
                    "\nsafestore: warning: failed to restore terminal echo.\n");
                return null;
            }
            stderr.printf ("\n");
            return line;
#endif
        }
    }
}
