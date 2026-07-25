namespace SafeStore {

    public enum StoreState {
        LOCKED,
        STARTING,
        MOUNTED,
        STOPPING,
        ERROR
    }

    public class CryfsController : Object {

        public signal void output (string line);
        public signal void state_changed (StoreState state, string detail);

        public StoreState state { get; private set; default = StoreState.LOCKED; }
        public string detail { get; private set; default = "Vault is locked"; }
        public bool process_active {
            get { return cryfs_process != null; }
        }

        private Subprocess? cryfs_process;
        private uint process_generation = 0;
        private bool expected_exit = false;

        public async string backend_version (string binary) throws Error {
            string? stdout_text;
            string? stderr_text;
            var process = new Subprocess (
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                binary, "--version"
            );
            yield process.communicate_utf8_async (
                null, null, out stdout_text, out stderr_text);
            string text = (stdout_text ?? "").strip ();
            if (text.length == 0) text = (stderr_text ?? "").strip ();
            if (!process.get_successful ()) {
                throw new IOError.FAILED (
                    "%s", text.length > 0 ? text : "CryFS returned an error.");
            }
            return text;
        }

        public void mount (string binary,
                           string vault_path,
                           string mount_path,
                           string password,
                           int idle_minutes,
                           bool create) throws Error {
            if (cryfs_process != null
                    || state == StoreState.STARTING
                    || state == StoreState.MOUNTED
                    || state == StoreState.STOPPING) {
                throw new IOError.BUSY ("A vault operation is already active.");
            }

            string starting_detail = create
                ? "Creating and mounting vault…"
                : "Unlocking vault…";
            output (
                create
                    ? "Creating a CryFS vault with XChaCha20-Poly1305."
                    : "Starting CryFS."
            );

            string[] argv = {};
            argv += binary;
            argv += "-f";
            if (create) {
                argv += "--cipher";
                argv += "xchacha20-poly1305";
            }
            if (idle_minutes > 0) {
                argv += "--unmount-idle";
                argv += idle_minutes.to_string ();
            }
            argv += vault_path;
            argv += mount_path;

            var launcher = new SubprocessLauncher (
                SubprocessFlags.STDIN_PIPE
                | SubprocessFlags.STDOUT_PIPE
                | SubprocessFlags.STDERR_PIPE
            );
            launcher.setenv ("CRYFS_FRONTEND", "noninteractive", true);
            launcher.setenv ("CRYFS_NO_UPDATE_CHECK", "true", true);
            string state_dir = Path.build_filename (
                Environment.get_user_data_dir (),
                "safestore",
                "cryfs-state"
            );
            if (DirUtils.create_with_parents (state_dir, 0700) != 0
                    && !FileUtils.test (state_dir, FileTest.IS_DIR)) {
                transition (
                    StoreState.ERROR,
                    "Could not create private CryFS state directory"
                );
                throw new IOError.FAILED ("%s", detail);
            }
            launcher.setenv ("CRYFS_LOCAL_STATE_DIR", state_dir, true);

            Subprocess process;
            try {
                process = launcher.spawnv (argv);
            } catch (Error error) {
                transition (StoreState.ERROR, "Could not start CryFS");
                throw error;
            }

            cryfs_process = process;
            transition (StoreState.STARTING, starting_detail);
            expected_exit = false;
            uint generation = ++process_generation;
            drain_stream.begin (
                process.get_stdout_pipe (), generation, false);
            drain_stream.begin (
                process.get_stderr_pipe (), generation, true);
            watch_process.begin (process, generation);

            try {
                var writer = new DataOutputStream (process.get_stdin_pipe ());
                writer.put_string (password);
                writer.put_byte ('\n');
                writer.close ();
                password = "";
            } catch (Error error) {
                password = "";
                transition (StoreState.ERROR, "Could not send password to CryFS");
                throw error;
            }

            confirm_mount.begin (
                process, generation, mount_path, idle_minutes);
        }

        private async void confirm_mount (Subprocess process,
                                          uint generation,
                                          string mount_path,
                                          int idle_minutes) {
            bool mounted = false;
            for (int attempt = 0;
                 attempt < 40
                    && generation == process_generation
                    && cryfs_process == process;
                 attempt++) {
                if (yield mount_is_active (mount_path)) {
                    mounted = true;
                    break;
                }
                yield delay (250);
            }
            if (mounted && cryfs_process == process
                    && state == StoreState.STARTING) {
                transition (
                    StoreState.MOUNTED,
                    idle_minutes > 0
                        ? "Mounted; auto-lock after %d idle minutes".printf (
                            idle_minutes)
                        : "Vault is mounted"
                );
                output ("Vault mounted successfully.");
            } else if (state == StoreState.ERROR || cryfs_process == null) {
                output ("Mount failed: " + detail);
            } else {
                transition (
                    StoreState.ERROR,
                    "CryFS is running, but no mount appeared within 10 seconds"
                );
                output (detail + "; use Lock to clean up.");
            }
        }

        public async void unmount (string binary,
                                   string mount_path) throws Error {
            if (cryfs_process == null) {
                throw new IOError.NOT_CONNECTED (
                    "No SafeStore-managed vault is mounted.");
            }

            transition (StoreState.STOPPING, "Locking vault…");
            expected_exit = true;
            output ("Requesting a clean CryFS unmount.");

            string unmount_binary = unmount_binary_for (binary);
            string? stdout_text;
            string? stderr_text;
            Subprocess process;
            try {
                process = new Subprocess (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                    unmount_binary, "--immediate", mount_path
                );
                yield process.communicate_utf8_async (
                    null, null, out stdout_text, out stderr_text);
            } catch (Error error) {
                expected_exit = false;
                transition (StoreState.MOUNTED, "Vault is still mounted");
                throw error;
            }

            append_multiline (stdout_text ?? "");
            append_multiline (stderr_text ?? "");
            if (!process.get_successful ()) {
                expected_exit = false;
                transition (
                    StoreState.MOUNTED,
                    "Unmount failed; close files using the vault and retry"
                );
                string reason = (stderr_text ?? "").strip ();
                throw new IOError.BUSY (
                    "%s", reason.length > 0 ? reason : "CryFS unmount failed.");
            }

            for (int attempt = 0;
                 attempt < 50 && cryfs_process != null;
                 attempt++) {
                yield delay (100);
            }
            if (cryfs_process != null) {
                transition (
                    StoreState.ERROR,
                    "Unmount command succeeded, but CryFS did not exit"
                );
                throw new IOError.TIMED_OUT ("%s", detail);
            }
            transition (StoreState.LOCKED, "Vault is locked");
            output ("Vault locked cleanly.");
        }

        private async void drain_stream (InputStream input,
                                         uint generation,
                                         bool is_error) {
            var stream = new DataInputStream (input);
            stream.set_newline_type (DataStreamNewlineType.ANY);
            try {
                while (generation == process_generation) {
                    size_t length;
                    string? line = yield stream.read_line_utf8_async (
                        Priority.DEFAULT, null, out length);
                    if (line == null) break;
                    string clean = line.strip ();
                    if (clean.length > 0) output (clean);
                }
            } catch (Error error) {
                if (generation == process_generation) {
                    output (
                        (is_error ? "CryFS error output ended: "
                                  : "CryFS output ended: ")
                        + error.message
                    );
                }
            }
        }

        private async void watch_process (Subprocess process,
                                          uint generation) {
            try {
                yield process.wait_async ();
            } catch (Error error) {
                if (generation == process_generation) {
                    output ("Could not monitor CryFS: " + error.message);
                }
            }
            if (generation != process_generation
                    || cryfs_process != process) return;

            cryfs_process = null;
            bool was_expected = expected_exit;
            expected_exit = false;
            if (was_expected || state == StoreState.STOPPING) {
                transition (StoreState.LOCKED, "Vault is locked");
                return;
            }

            int status = 1;
            if (process.get_if_exited ()) status = process.get_exit_status ();
            string message = exit_message (status);
            transition (
                status == 0 ? StoreState.LOCKED : StoreState.ERROR,
                message
            );
        }

        private static string exit_message (int status) {
            switch (status) {
            case 0: return "CryFS exited; vault is locked";
            case 10: return "CryFS rejected the command-line options";
            case 11: return "Wrong vault password";
            case 12: return "CryFS rejected an empty password";
            case 13: return "Vault format is newer than this CryFS version";
            case 14: return "Vault requires an explicit filesystem upgrade";
            case 15: return "Vault uses an unsupported cipher";
            case 16: return "Encrypted vault folder is inaccessible";
            case 17: return "Mount location is inaccessible";
            case 18: return "Encrypted vault is inside the mount location";
            case 19: return "Selected folder is not a valid CryFS vault";
            case 20: return "CryFS detected a replaced filesystem";
            case 21: return "CryFS detected a changed encryption key";
            case 22: return "CryFS integrity setup does not match";
            case 23: return "Vault is configured for a single client";
            case 24: return "CryFS detected an earlier integrity violation";
            case 25: return "CryFS detected a filesystem integrity violation";
            default:
                return "CryFS exited with status %d".printf (status);
            }
        }

        private void transition (StoreState new_state, string new_detail) {
            state = new_state;
            detail = new_detail;
            state_changed (state, detail);
        }

        private void append_multiline (string text) {
            foreach (string line in text.split ("\n")) {
                string clean = line.strip ();
                if (clean.length > 0) output (clean);
            }
        }

        private static string unmount_binary_for (string cryfs_binary) {
            string directory = Path.get_dirname (cryfs_binary);
            string basename = Path.get_basename (cryfs_binary);
            if (directory == "." && basename == cryfs_binary) {
                return "cryfs-unmount";
            }
#if WINDOWS
            string executable = basename.ascii_down ();
            if (executable.has_suffix (".exe")) {
                return Path.build_filename (
                    directory, "cryfs-unmount.exe");
            }
#endif
            return Path.build_filename (directory, "cryfs-unmount");
        }

        private static async bool mount_is_active (string mount_path) {
#if WINDOWS
            return FileUtils.test (
                PathPolicy.normalize (mount_path) + "\\",
                FileTest.IS_DIR
            );
#elif LINUX
            string contents;
            try {
                FileUtils.get_contents ("/proc/self/mountinfo", out contents);
            } catch (Error error) {
                return false;
            }
            string wanted = PathPolicy.normalize (mount_path);
            foreach (string line in contents.split ("\n")) {
                string[] fields = line.split (" ");
                if (fields.length > 4
                        && decode_mount_path (fields[4]) == wanted) {
                    return true;
                }
            }
            return false;
#else
            try {
                string? stdout_text;
                string? stderr_text;
                var process = new Subprocess (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                    "/sbin/mount"
                );
                yield process.communicate_utf8_async (
                    null, null, out stdout_text, out stderr_text);
                if (!process.get_successful ()) return false;
                string marker = " on %s (".printf (
                    PathPolicy.normalize (mount_path));
                foreach (string line in (stdout_text ?? "").split ("\n")) {
                    if (line.contains (marker)) return true;
                }
            } catch (Error error) {
                return false;
            }
            return false;
#endif
        }

#if LINUX
        private static string decode_mount_path (string path) {
            return path
                .replace ("\\040", " ")
                .replace ("\\011", "\t")
                .replace ("\\012", "\n")
                .replace ("\\134", "\\");
        }
#endif

        private static async void delay (uint milliseconds) {
            SourceFunc callback = delay.callback;
            Timeout.add (milliseconds, () => {
                callback ();
                return Source.REMOVE;
            });
            yield;
        }
    }
}
