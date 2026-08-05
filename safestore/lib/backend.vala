namespace SafeStore {

    public class CryfsBackend : Object {

        public static string exit_message (int status) {
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

        public static string unmount_binary_for (string cryfs_binary) {
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

        public static string state_dir () throws Error {
            string dir = Path.build_filename (
                Environment.get_user_data_dir (),
                "safestore",
                "cryfs-state"
            );
            if (DirUtils.create_with_parents (dir, 0700) != 0
                    && !FileUtils.test (dir, FileTest.IS_DIR)) {
                throw new IOError.FAILED (
                    "Could not create private CryFS state directory: %s", dir);
            }
            return dir;
        }

        public static void apply_environment (SubprocessLauncher launcher)
                                              throws Error {
            launcher.setenv ("CRYFS_FRONTEND", "noninteractive", true);
            launcher.setenv ("CRYFS_NO_UPDATE_CHECK", "true", true);
            launcher.setenv ("CRYFS_LOCAL_STATE_DIR", state_dir (), true);
        }
    }
}
