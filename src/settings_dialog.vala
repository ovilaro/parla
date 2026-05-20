namespace Dc {

    public delegate void SettingWriter (KeyFile kf);

    public enum SidebarMode {
        FULL = 0,
        COMPACT = 1,
        HIDDEN = 2;

        public SidebarMode next () {
            switch (this) {
            case FULL: return COMPACT;
            case COMPACT: return HIDDEN;
            default: return FULL;
            }
        }
    }

    public class SettingsManager : Object {

        public int double_click_action { get; set; default = 0; }
        public bool markdown_rendering { get; set; default = false; }
        public bool shift_enter_sends { get; set; default = false; }
        public bool notifications_enabled { get; set; default = true; }
        public string rpc_server_path { get; set; default = ""; }
        public RpcServerSource rpc_server_source { get; set; default = RpcServerSource.AUTO; }
        public SidebarMode sidebar_mode { get; set; default = SidebarMode.FULL; }

        public static string get_config_path () {
            return Path.build_filename (
                Environment.get_user_config_dir (),
                "parla", "settings.ini");
        }

        public void load () {
            var kf = new KeyFile ();
            try { kf.load_from_file (get_config_path (), KeyFileFlags.NONE); }
            catch (Error e) { /* file may not exist — helpers return defaults */ }
            double_click_action = kf_int (kf, "double_click_action", 0);
            markdown_rendering = kf_bool (kf, "markdown_rendering", false);
            Markdown.enabled = markdown_rendering;
            shift_enter_sends = kf_bool (kf, "shift_enter_sends", false);
            notifications_enabled = kf_bool (kf, "notifications_enabled", true);
            rpc_server_path = kf_str (kf, "rpc_server_path", "");
            int default_source = rpc_server_path.length > 0
                ? (int) RpcServerSource.CUSTOM
                : (int) RpcServerSource.AUTO;
            int source = kf_int (kf, "rpc_server_source", default_source);
            if (source < 0 || source > 2) source = default_source;
            rpc_server_source = (RpcServerSource) source;
            int sb = kf_int (kf, "sidebar_mode", (int) SidebarMode.FULL);
            if (sb < 0 || sb > 2) sb = (int) SidebarMode.FULL;
            sidebar_mode = (SidebarMode) sb;
        }

        private static int kf_int (KeyFile kf, string k, int d) {
            try { return kf.get_integer ("General", k); } catch { return d; }
        }

        private static bool kf_bool (KeyFile kf, string k, bool d) {
            try { return kf.get_boolean ("General", k); } catch { return d; }
        }

        private static string kf_str (KeyFile kf, string k, string d) {
            try { return kf.get_string ("General", k); } catch { return d; }
        }

        public void save_double_click_action (int v) {
            double_click_action = v;
            save_to_file ((kf) => { kf.set_integer ("General", "double_click_action", v); });
        }

        public void save_markdown_rendering (bool v) {
            markdown_rendering = v; Markdown.enabled = v;
            save_to_file ((kf) => { kf.set_boolean ("General", "markdown_rendering", v); });
        }

        public void save_shift_enter_sends (bool v) {
            shift_enter_sends = v;
            save_to_file ((kf) => { kf.set_boolean ("General", "shift_enter_sends", v); });
        }

        public void save_notifications_enabled (bool v) {
            notifications_enabled = v;
            save_to_file ((kf) => { kf.set_boolean ("General", "notifications_enabled", v); });
        }

        public void save_rpc_server_path (string v) {
            rpc_server_path = v;
            save_to_file ((kf) => { kf.set_string ("General", "rpc_server_path", v); });
        }

        public void save_rpc_server_source (RpcServerSource v) {
            rpc_server_source = v;
            save_to_file ((kf) => {
                kf.set_integer ("General", "rpc_server_source", (int) v);
            });
        }

        public void save_sidebar_mode (SidebarMode v) {
            sidebar_mode = v;
            save_to_file ((kf) => {
                kf.set_integer ("General", "sidebar_mode", (int) v);
            });
        }

        public void save_to_file (SettingWriter writer) {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (get_config_path (), KeyFileFlags.NONE);
            } catch (Error e) { /* file may not exist yet */ }
            writer (kf);
            try {
                var dir = Path.get_dirname (get_config_path ());
                DirUtils.create_with_parents (dir, 0755);
                kf.save_to_file (get_config_path ());
            } catch (Error e) {
                warning ("Failed to save settings: %s", e.message);
            }
        }
    }

    public class SettingsDialog : Adw.Dialog {

        private Gtk.Box content;
        private unowned Window app_window;
        private Adw.ActionRow rpc_row;
        private Adw.ActionRow rpc_version_row;
        private Gtk.DropDown rpc_source_dropdown;
        private Gtk.Button rpc_choose_btn;
        private Gtk.Button rpc_update_btn;
        private bool syncing_rpc_source = false;
        private uint rpc_version_request = 0;
        private string? rpc_current_version = null;
        private bool rpc_update_check_available = false;

        public SettingsDialog (Window window) {
            this.app_window = window;
            this.title = "Settings";
            this.content_width = 400;
            this.content_height = 480;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = true;
            box.append (header);

            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
            content.margin_start = 16;
            content.margin_end = 16;
            content.margin_top = 12;
            content.margin_bottom = 16;

            /* Behavior section */
            var behavior_label = new Gtk.Label ("Behavior");
            behavior_label.add_css_class ("title-3");
            behavior_label.halign = Gtk.Align.START;
            content.append (behavior_label);

            var behavior_list = new Gtk.ListBox ();
            behavior_list.selection_mode = Gtk.SelectionMode.NONE;
            behavior_list.add_css_class ("boxed-list");

            var dblclick_row = new Adw.ActionRow ();
            dblclick_row.title = "Double-click on message";
            dblclick_row.subtitle = "Action when a message is double-clicked";

            string[] dblclick_labels = {
                "Reply to message",
                "React with ❤️",
                "React with 👍",
                "Open user profile",
                "Do nothing"
            };

            var dblclick_combo = new Gtk.DropDown.from_strings (dblclick_labels);
            dblclick_combo.selected = app_window.settings.double_click_action;
            dblclick_combo.valign = Gtk.Align.CENTER;
            dblclick_combo.notify["selected"].connect (() => {
                app_window.settings.save_double_click_action ((int) dblclick_combo.selected);
            });
            dblclick_row.add_suffix (dblclick_combo);
            dblclick_row.activatable_widget = dblclick_combo;

            behavior_list.append (dblclick_row);

            var md_row = new Adw.ActionRow ();
            md_row.title = "Markdown rendering";
            md_row.subtitle = "Format bold, italic, code and headings";

            var md_switch = new Gtk.Switch ();
            md_switch.active = Markdown.enabled;
            md_switch.valign = Gtk.Align.CENTER;
            md_switch.notify["active"].connect (() => {
                app_window.settings.save_markdown_rendering (md_switch.active);
            });
            md_row.add_suffix (md_switch);
            md_row.activatable_widget = md_switch;

            behavior_list.append (md_row);

            var shift_row = new Adw.ActionRow ();
            shift_row.title = "Shift+Return sends message";
            shift_row.subtitle = "When on, Return inserts a newline and Shift+Return sends";

            var shift_switch = new Gtk.Switch ();
            shift_switch.active = app_window.settings.shift_enter_sends;
            shift_switch.valign = Gtk.Align.CENTER;
            shift_switch.notify["active"].connect (() => {
                app_window.settings.save_shift_enter_sends (shift_switch.active);
            });
            shift_row.add_suffix (shift_switch);
            shift_row.activatable_widget = shift_switch;

            behavior_list.append (shift_row);

            var notif_row = new Adw.ActionRow ();
            notif_row.title = "Desktop notifications";
            notif_row.subtitle = "Notify on incoming messages when the window is not focused";

            var notif_switch = new Gtk.Switch ();
            notif_switch.active = app_window.settings.notifications_enabled;
            notif_switch.valign = Gtk.Align.CENTER;
            notif_switch.notify["active"].connect (() => {
                app_window.settings.save_notifications_enabled (notif_switch.active);
            });
            notif_row.add_suffix (notif_switch);
            notif_row.activatable_widget = notif_switch;

            behavior_list.append (notif_row);
            content.append (behavior_list);

            /* Advanced section */
            var advanced_label = new Gtk.Label ("Advanced");
            advanced_label.add_css_class ("title-3");
            advanced_label.halign = Gtk.Align.START;
            content.append (advanced_label);

            var advanced_list = new Gtk.ListBox ();
            advanced_list.selection_mode = Gtk.SelectionMode.NONE;
            advanced_list.add_css_class ("boxed-list");

            rpc_row = new Adw.ActionRow ();
            rpc_row.title = "RPC server";

            string[] rpc_source_labels = {
                "Auto",
                "Custom",
                "Desktop"
            };
            rpc_source_dropdown = new Gtk.DropDown.from_strings (rpc_source_labels);
            rpc_source_dropdown.selected = (uint) app_window.settings.rpc_server_source;
            rpc_source_dropdown.valign = Gtk.Align.CENTER;
            rpc_source_dropdown.notify["selected"].connect (on_rpc_source_changed);
            rpc_row.add_suffix (rpc_source_dropdown);
            rpc_row.activatable_widget = rpc_source_dropdown;

            rpc_choose_btn = new Gtk.Button.with_label ("Pick");
            rpc_choose_btn.valign = Gtk.Align.CENTER;
            rpc_choose_btn.add_css_class ("flat");
            rpc_choose_btn.tooltip_text = "Pick a deltachat-rpc-server binary";
            rpc_choose_btn.clicked.connect (() => { on_browse_rpc_server.begin (); });
            rpc_row.add_suffix (rpc_choose_btn);

            var rpc_download_btn = new Gtk.Button.with_label ("Get");
            rpc_download_btn.valign = Gtk.Align.CENTER;
            rpc_download_btn.add_css_class ("flat");
            rpc_download_btn.tooltip_text = "Open standalone deltachat-rpc-server releases";
            rpc_download_btn.clicked.connect (() => { open_rpc_download_page.begin (); });
            rpc_row.add_suffix (rpc_download_btn);

            advanced_list.append (rpc_row);

            rpc_version_row = new Adw.ActionRow ();
            rpc_version_row.title = "RPC server version";
            rpc_version_row.subtitle = "Checking...";
            rpc_update_btn = new Gtk.Button.with_label ("Check");
            rpc_update_btn.valign = Gtk.Align.CENTER;
            rpc_update_btn.add_css_class ("flat");
            rpc_update_btn.tooltip_text = "Check latest deltachat-rpc-server release";
            rpc_update_btn.clicked.connect (() => { check_rpc_updates.begin (); });
            rpc_version_row.add_suffix (rpc_update_btn);
            advanced_list.append (rpc_version_row);

            content.append (advanced_list);
            update_rpc_row ();

            var reset_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            reset_box.margin_top = 8;

            var reset_btn = new Gtk.Button.with_label ("Factory Reset");
            reset_btn.add_css_class ("destructive-action");
            reset_btn.tooltip_text = "Delete all Parla configuration and start fresh";
            reset_btn.clicked.connect (on_reset_settings);
            reset_box.append (reset_btn);

            var reset_label = new Gtk.Label ("Remove all settings and close the app");
            reset_label.add_css_class ("dim-label");
            reset_label.valign = Gtk.Align.CENTER;
            reset_box.append (reset_label);

            content.append (reset_box);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = content;
            box.append (scroll);

            this.child = box;
        }

        private void update_rpc_row () {
            sync_rpc_source_dropdown ();
            rpc_choose_btn.sensitive =
                app_window.settings.rpc_server_source == RpcServerSource.CUSTOM;

            string custom = app_window.settings.rpc_server_path;
            RpcServerSource source = app_window.settings.rpc_server_source;
            string? found = AccountFinder.find_rpc_server (custom, source);
            switch (source) {
            case RpcServerSource.CUSTOM:
                if (custom.length == 0) {
                    rpc_row.subtitle = "No custom binary selected";
                    rpc_row.tooltip_text = "Choose a deltachat-rpc-server binary";
                } else {
                    rpc_row.subtitle = found != null
                        ? "Using custom binary"
                        : "Custom path is not executable";
                    rpc_row.tooltip_text = custom;
                }
                break;
            case RpcServerSource.DESKTOP:
                string? desktop_dir = AccountFinder.find_desktop_data_dir ();
                if (found == null) {
                    rpc_row.subtitle = "Delta Chat Desktop server not found";
                    rpc_row.tooltip_text =
                        "Install Delta Chat Desktop or choose another server source";
                } else if (desktop_dir == null) {
                    rpc_row.subtitle = "Desktop account store not found";
                    rpc_row.tooltip_text =
                        "Sign in to Delta Chat Desktop or choose another server source";
                } else {
                    rpc_row.subtitle =
                        "Using Delta Chat Desktop server and accounts";
                    rpc_row.tooltip_text = "%s\n%s".printf (found, desktop_dir);
                }
                break;
            case RpcServerSource.AUTO:
            default:
                rpc_row.subtitle = found != null
                    ? "Using Parla or system server"
                    : "Standalone server not found";
                rpc_row.tooltip_text = found
                    ?? "Install deltachat-rpc-server or choose a custom binary";
                break;
            }
            update_rpc_version_row.begin (found);
        }

        private async void update_rpc_version_row (string? rpc_path) {
            uint request_id = ++rpc_version_request;
            if (rpc_path == null || rpc_path.length == 0) {
                rpc_version_row.subtitle = "Not available";
                rpc_version_row.tooltip_text = "No executable server selected";
                rpc_current_version = null;
                rpc_update_check_available = false;
                rpc_update_btn.sensitive = false;
                return;
            }

            rpc_version_row.subtitle = "Checking...";
            rpc_version_row.tooltip_text = rpc_path;
            rpc_current_version = null;
            rpc_update_check_available = false;
            rpc_update_btn.sensitive = false;

            try {
                var process = new Subprocess (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                    rpc_path, "--version");
                string? stdout_buf;
                string? stderr_buf;
                yield process.communicate_utf8_async (
                    null, null, out stdout_buf, out stderr_buf);

                if (request_id != rpc_version_request) return;

                string version = ((stdout_buf ?? "").strip ().length > 0)
                    ? (stdout_buf ?? "").strip ()
                    : (stderr_buf ?? "").strip ();
                if (process.get_successful () && version.length > 0) {
                    rpc_version_row.subtitle = version;
                    rpc_current_version = extract_version (version);
                    rpc_update_check_available = true;
                    rpc_update_btn.sensitive = true;
                } else {
                    rpc_version_row.subtitle = "Unable to read version";
                    rpc_current_version = null;
                    rpc_update_check_available = false;
                    rpc_update_btn.sensitive = false;
                }
            } catch (Error e) {
                if (request_id != rpc_version_request) return;
                rpc_version_row.subtitle = "Unable to read version";
                rpc_version_row.tooltip_text = "%s\n%s".printf (rpc_path, e.message);
                rpc_current_version = null;
                rpc_update_check_available = false;
                rpc_update_btn.sensitive = false;
            }
        }

        private async void check_rpc_updates () {
            if (rpc_update_btn == null || !rpc_update_btn.sensitive) return;

            rpc_update_btn.sensitive = false;
            string previous_subtitle = rpc_version_row.subtitle;
            rpc_version_row.subtitle = "Checking for updates...";

            try {
                string latest_tag = yield fetch_latest_rpc_release_tag ();
                string? latest_version = extract_version (latest_tag);
                if (latest_version == null) {
                    rpc_version_row.subtitle = previous_subtitle;
                    app_window.show_toast ("Could not parse latest RPC server version");
                    return;
                }

                if (rpc_current_version == null) {
                    rpc_version_row.subtitle =
                        "Latest available: %s".printf (latest_version);
                    app_window.show_toast ("Latest RPC server: " + latest_version);
                } else if (rpc_current_version != latest_version) {
                    rpc_version_row.subtitle = "Latest: %s (installed %s)".printf (
                        latest_version, rpc_current_version);
                    app_window.show_toast ("RPC server version differs: " + latest_version);
                } else {
                    rpc_version_row.subtitle = "Up to date: %s".printf (rpc_current_version);
                    app_window.show_toast ("RPC server is up to date");
                }
                rpc_version_row.tooltip_text =
                    "Latest release: https://github.com/chatmail/core/releases/tag/%s".printf (
                        latest_tag);
            } catch (Error e) {
                rpc_version_row.subtitle = previous_subtitle;
                app_window.show_toast ("Update check failed: " + e.message);
            } finally {
                rpc_update_btn.sensitive = rpc_update_check_available;
            }
        }

        private async string fetch_latest_rpc_release_tag () throws Error {
            var client = new SocketClient ();
            client.timeout = 15;
            var tcp = yield client.connect_to_host_async ("github.com", 443, null);
            var identity = new NetworkAddress ("github.com", 443);
            var tls = TlsClientConnection.new (tcp, identity);
            if (tls == null) {
                throw new IOError.FAILED ("Unable to create TLS connection");
            }
            yield tls.handshake_async (Priority.DEFAULT, null);

            string request =
                "HEAD /chatmail/core/releases/latest HTTP/1.1\r\n" +
                "Host: github.com\r\n" +
                "User-Agent: Parla\r\n" +
                "Accept: */*\r\n" +
                "Connection: close\r\n\r\n";

            size_t written;
            yield tls.output_stream.write_all_async (
                request.data, Priority.DEFAULT, null, out written);

            var reader = new DataInputStream (tls.input_stream);
            reader.set_newline_type (DataStreamNewlineType.LF);

            size_t len;
            string? status_line = yield reader.read_line_utf8_async (
                Priority.DEFAULT, null, out len);
            int status = parse_http_status (status_line ?? "");
            string? location = null;

            string? line;
            while ((line = yield reader.read_line_utf8_async (
                        Priority.DEFAULT, null, out len)) != null) {
                string stripped = line.strip ();
                if (stripped.length == 0) break;
                if (stripped.down ().has_prefix ("location:")) {
                    location = stripped.substring ("location:".length).strip ();
                }
            }

            try {
                yield tls.close_async (Priority.DEFAULT, null);
            } catch (Error e) {
                /* The response has already been read. */
            }

            if (status < 300 || status >= 400 || location == null) {
                throw new IOError.FAILED (
                    "GitHub returned HTTP status %d".printf (status));
            }

            string? tag = extract_release_tag (location);
            if (tag == null) {
                throw new IOError.FAILED ("GitHub response did not include a release tag");
            }
            return tag;
        }

        private static int parse_http_status (string status_line) {
            string[] parts = status_line.split (" ");
            if (parts.length < 2) return 0;
            return int.parse (parts[1]);
        }

        private static string? extract_release_tag (string location) {
            int idx = location.last_index_of ("/tag/");
            if (idx < 0) return null;

            string tag = location.substring (idx + "/tag/".length);
            int q = tag.index_of ("?");
            if (q >= 0) tag = tag.substring (0, q);
            int hash = tag.index_of ("#");
            if (hash >= 0) tag = tag.substring (0, hash);
            tag = tag.strip ();
            return tag.length > 0 ? tag : null;
        }

        private static string? extract_version (string text) {
            int start = -1;
            int end = -1;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (start < 0) {
                    if (c >= '0' && c <= '9') {
                        start = i;
                        end = i + 1;
                    }
                } else if ((c >= '0' && c <= '9') || c == '.') {
                    end = i + 1;
                } else {
                    break;
                }
            }
            if (start < 0 || end <= start) return null;

            string version = text.substring (start, end - start);
            while (version.has_suffix (".")) {
                version = version.substring (0, version.length - 1);
            }
            return version.length > 0 ? version : null;
        }

        private void sync_rpc_source_dropdown () {
            syncing_rpc_source = true;
            rpc_source_dropdown.selected =
                (uint) app_window.settings.rpc_server_source;
            syncing_rpc_source = false;
        }

        private void on_rpc_source_changed () {
            if (syncing_rpc_source) return;

            RpcServerSource source = (RpcServerSource) rpc_source_dropdown.selected;
            if (source == RpcServerSource.CUSTOM &&
                app_window.settings.rpc_server_path.length == 0) {
                on_browse_rpc_server.begin ();
                return;
            }

            app_window.settings.save_rpc_server_source (source);
            app_window.show_toast ("RPC server preference saved. Restart to apply.");
            update_rpc_row ();
        }

        private async void on_browse_rpc_server () {
            var dlg = new Gtk.FileDialog ();
            dlg.title = "Locate deltachat-rpc-server";
            dlg.modal = true;

            string start = app_window.settings.rpc_server_path;
            if (start.length == 0) start = AccountFinder.find_rpc_server () ?? "";
            if (start.length > 0) dlg.initial_file = File.new_for_path (start);

            try {
                var file = yield dlg.open (app_window, null);
                if (file != null) {
                    string? path = file.get_path ();
                    if (path != null && FileUtils.test (path, FileTest.IS_EXECUTABLE)) {
                        app_window.settings.save_rpc_server_path (path);
                        app_window.settings.save_rpc_server_source (RpcServerSource.CUSTOM);
                        app_window.show_toast ("RPC server path saved. Restart to apply.");
                    } else {
                        show_error (app_window, "Selected file is not an executable binary.");
                    }
                }
            } catch (Error e) {
                if (!(e is Gtk.DialogError) && !(e is IOError.CANCELLED))
                    show_error (app_window, e.message);
            }
            update_rpc_row ();
        }

        private async void open_rpc_download_page () {
            try {
                yield (new Gtk.UriLauncher (
                    "https://github.com/chatmail/core/releases/latest")).launch (
                    app_window, null);
            } catch (Error e) {
                show_error (app_window, "Unable to open download page: " + e.message);
            }
        }

        private void on_reset_settings () {
            confirm_action (app_window, "Factory Reset",
                "This will delete all Parla configuration files and close the application. " +
                "Your Delta Chat accounts and messages are not affected.",
                "reset", "Reset & Close", () => {
                    delete_parla_config ();
                    app_window.application.quit ();
                });
        }

        private static void delete_parla_config () {
            var dir = Path.build_filename (
                Environment.get_user_config_dir (), "parla");
            FileUtils.unlink (Path.build_filename (dir, "settings.ini"));
            DirUtils.remove (dir);
        }
    }
}
