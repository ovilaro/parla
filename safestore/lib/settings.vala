namespace SafeStore {

    public class Settings : Object {

        /* The vault and mount locations are not configurable: they always
           follow the Delta Chat accounts path so that SafeStore, Parla, and
           deltachat-rpc-server agree on where the data lives. */
        public string vault_path {
            owned get { return AccountsPath.vault_path (); }
        }
        public string mount_path {
            owned get { return AccountsPath.mount_path (); }
        }
        public string cryfs_binary { get; set; }
        public int idle_minutes { get; set; }

        public Settings () {
            cryfs_binary = Environment.get_variable ("SAFESTORE_CRYFS") ?? "cryfs";
            idle_minutes = 0;
            load ();
        }

        private static string config_path () {
            return Path.build_filename (
                Environment.get_user_config_dir (),
                "safestore",
                "settings.ini"
            );
        }

        private void load () {
            var keyfile = new KeyFile ();
            try {
                keyfile.load_from_file (config_path (), KeyFileFlags.NONE);
            } catch (Error error) {
                return;
            }

            cryfs_binary = read_string (
                keyfile, "cryfs_binary", cryfs_binary);
            idle_minutes = read_integer (
                keyfile, "idle_minutes", idle_minutes);
            if (idle_minutes < 0) idle_minutes = 0;
            if (idle_minutes > 24 * 60) idle_minutes = 24 * 60;
        }

        public void save () {
            var keyfile = new KeyFile ();
            keyfile.set_string ("SafeStore", "cryfs_binary", cryfs_binary);
            keyfile.set_integer ("SafeStore", "idle_minutes", idle_minutes);

            try {
                string parent = Path.get_dirname (config_path ());
                DirUtils.create_with_parents (parent, 0700);
                keyfile.save_to_file (config_path ());
            } catch (Error error) {
                warning ("Could not save SafeStore settings: %s", error.message);
            }
        }

        private static string read_string (KeyFile keyfile,
                                           string key,
                                           string fallback) {
            try {
                return keyfile.get_string ("SafeStore", key);
            } catch (Error error) {
                return fallback;
            }
        }

        private static int read_integer (KeyFile keyfile,
                                         string key,
                                         int fallback) {
            try {
                return keyfile.get_integer ("SafeStore", key);
            } catch (Error error) {
                return fallback;
            }
        }
    }
}
