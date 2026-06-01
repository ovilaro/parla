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

    public enum MessageStyle {
        BUBBLES = 0,
        IRC = 1;
    }

    public class SettingsManager : Object {

        public signal void appearance_changed ();

        public int double_click_action { get; set; default = 0; }
        public bool markdown_rendering { get; set; default = false; }
        public bool shift_enter_sends { get; set; default = false; }
        public bool notifications_enabled { get; set; default = true; }
        public bool minimize_to_tray { get; set; default = false; }
        public string rpc_server_path { get; set; default = ""; }
        public RpcServerSource rpc_server_source { get; set; default = RpcServerSource.AUTO; }
        public bool rpc_check_updates_on_startup { get; set; default = true; }
        public SidebarMode sidebar_mode { get; set; default = SidebarMode.FULL; }
        public string default_account_addr { get; set; default = ""; }
        public MessageStyle message_style { get; set; default = MessageStyle.BUBBLES; }
        public string accent_color { get; set; default = ""; }

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
            minimize_to_tray = kf_bool (kf, "minimize_to_tray", false);
            rpc_server_path = kf_str (kf, "rpc_server_path", "");
            /* Auto is always the default: a fresh install self-onboards the
               engine, and the source is only Custom/Desktop when explicitly
               chosen (those writes always persist the rpc_server_source key). */
            int source = kf_int (kf, "rpc_server_source", (int) RpcServerSource.AUTO);
            if (source < 0 || source > 2) source = (int) RpcServerSource.AUTO;
            rpc_server_source = (RpcServerSource) source;
            rpc_check_updates_on_startup =
                kf_bool (kf, "rpc_check_updates_on_startup", true);
            int sb = kf_int (kf, "sidebar_mode", (int) SidebarMode.FULL);
            if (sb < 0 || sb > 2) sb = (int) SidebarMode.FULL;
            sidebar_mode = (SidebarMode) sb;
            default_account_addr = kf_str (kf, "default_account_addr", "");
            int ms = kf_int (kf, "message_style", (int) MessageStyle.BUBBLES);
            if (ms < 0 || ms > 1) ms = (int) MessageStyle.BUBBLES;
            message_style = (MessageStyle) ms;
            accent_color = kf_str (kf, "accent_color", "");
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

        public void save_minimize_to_tray (bool v) {
            minimize_to_tray = v;
            save_to_file ((kf) => { kf.set_boolean ("General", "minimize_to_tray", v); });
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

        public void save_rpc_check_updates_on_startup (bool v) {
            rpc_check_updates_on_startup = v;
            save_to_file ((kf) => {
                kf.set_boolean ("General", "rpc_check_updates_on_startup", v);
            });
        }

        public void save_sidebar_mode (SidebarMode v) {
            sidebar_mode = v;
            save_to_file ((kf) => {
                kf.set_integer ("General", "sidebar_mode", (int) v);
            });
        }

        public void save_default_account_addr (string v) {
            default_account_addr = v;
            save_to_file ((kf) => {
                kf.set_string ("General", "default_account_addr", v);
            });
        }

        public void save_message_style (MessageStyle v) {
            message_style = v;
            save_to_file ((kf) => {
                kf.set_integer ("General", "message_style", (int) v);
            });
            appearance_changed ();
        }

        public void save_accent_color (string v) {
            accent_color = v;
            save_to_file ((kf) => {
                kf.set_string ("General", "accent_color", v);
            });
            appearance_changed ();
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
        private Gtk.Button rpc_download_btn;
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

            var tray_row = new Adw.ActionRow ();
            tray_row.title = "Minimize to status bar";
            tray_row.subtitle =
                "Closing the window keeps Parla running in the status bar; "
                + "notifications still appear";

            var tray_switch = new Gtk.Switch ();
            tray_switch.active = app_window.settings.minimize_to_tray;
            tray_switch.valign = Gtk.Align.CENTER;
            tray_switch.notify["active"].connect (() => {
                app_window.settings.save_minimize_to_tray (tray_switch.active);
            });
            tray_row.add_suffix (tray_switch);
            tray_row.activatable_widget = tray_switch;

            behavior_list.append (tray_row);
            content.append (behavior_list);

            /* Appearance section */
            var appearance_label = new Gtk.Label ("Appearance");
            appearance_label.add_css_class ("title-3");
            appearance_label.halign = Gtk.Align.START;
            content.append (appearance_label);

            var appearance_list = new Gtk.ListBox ();
            appearance_list.selection_mode = Gtk.SelectionMode.NONE;
            appearance_list.add_css_class ("boxed-list");

            var style_row = new Adw.ActionRow ();
            style_row.title = "Message style";
            style_row.subtitle = "Use chat bubbles or compact IRC-style lines";

            string[] style_labels = { "Bubbles", "IRC" };
            var style_combo = new Gtk.DropDown.from_strings (style_labels);
            style_combo.selected = (uint) app_window.settings.message_style;
            style_combo.valign = Gtk.Align.CENTER;
            style_combo.notify["selected"].connect (() => {
                app_window.settings.save_message_style (
                    (MessageStyle) style_combo.selected);
            });
            style_row.add_suffix (style_combo);
            style_row.activatable_widget = style_combo;
            appearance_list.append (style_row);

            var accent_row = new Adw.ActionRow ();
            accent_row.title = "Accent color";
            accent_row.subtitle = "Override the system accent color";

            var accent_btn = new Gtk.ColorDialogButton (new Gtk.ColorDialog ());
            accent_btn.valign = Gtk.Align.CENTER;
            apply_accent_to_button (accent_btn, app_window.settings.accent_color);
            accent_btn.notify["rgba"].connect (() => {
                Gdk.RGBA c = accent_btn.get_rgba ();
                string hex = "#%02x%02x%02x".printf (
                    (uint) (c.red * 255), (uint) (c.green * 255),
                    (uint) (c.blue * 255));
                app_window.settings.save_accent_color (hex);
            });

            var accent_reset_btn = new Gtk.Button.from_icon_name ("edit-undo-symbolic");
            accent_reset_btn.valign = Gtk.Align.CENTER;
            accent_reset_btn.add_css_class ("flat");
            accent_reset_btn.tooltip_text = "Use system accent color";
            accent_reset_btn.clicked.connect (() => {
                app_window.settings.save_accent_color ("");
                apply_accent_to_button (accent_btn, "");
            });

            accent_row.add_suffix (accent_btn);
            accent_row.add_suffix (accent_reset_btn);
            appearance_list.append (accent_row);

            content.append (appearance_list);

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

            rpc_download_btn = new Gtk.Button.with_label ("Get");
            rpc_download_btn.valign = Gtk.Align.CENTER;
            rpc_download_btn.add_css_class ("flat");
            rpc_download_btn.tooltip_text =
                "Download the latest deltachat-rpc-server into Parla's data dir";
            rpc_download_btn.clicked.connect (() => { install_managed_server.begin (); });
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

            var rpc_autocheck_row = new Adw.ActionRow ();
            rpc_autocheck_row.title = "Check for engine updates on startup";
            rpc_autocheck_row.subtitle =
                "Notify when a newer deltachat-rpc-server is available";
            var autocheck_switch = new Gtk.Switch ();
            autocheck_switch.active =
                app_window.settings.rpc_check_updates_on_startup;
            autocheck_switch.valign = Gtk.Align.CENTER;
            autocheck_switch.notify["active"].connect (() => {
                app_window.settings.save_rpc_check_updates_on_startup (
                    autocheck_switch.active);
            });
            rpc_autocheck_row.add_suffix (autocheck_switch);
            rpc_autocheck_row.activatable_widget = autocheck_switch;
            advanced_list.append (rpc_autocheck_row);

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
                    rpc_current_version = RpcInstaller.extract_version (version);
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
                string latest_tag = yield RpcInstaller.fetch_latest_tag ();
                string? latest_version = RpcInstaller.extract_version (latest_tag);
                if (latest_version == null) {
                    rpc_version_row.subtitle = previous_subtitle;
                    app_window.show_toast ("Could not parse latest RPC server version");
                    return;
                }

                bool managed_active =
                    AccountFinder.find_rpc_server (
                        app_window.settings.rpc_server_path,
                        app_window.settings.rpc_server_source)
                    == AccountFinder.get_managed_rpc_path ();

                if (rpc_current_version == null) {
                    rpc_version_row.subtitle =
                        "Latest available: %s".printf (latest_version);
                    app_window.show_toast ("Latest RPC server: " + latest_version);
                } else if (rpc_current_version != latest_version) {
                    rpc_version_row.subtitle = "Latest: %s (installed %s)".printf (
                        latest_version, rpc_current_version);
                    if (managed_active) {
                        app_window.show_toast (
                            "Update available: %s — press Get to install".printf (
                                latest_version));
                    } else {
                        app_window.show_toast (
                            "RPC server version differs: " + latest_version);
                    }
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

        /* One-click: download the latest server into Parla's data dir. */
        private async void install_managed_server () {
            if (RpcInstaller.detect_asset_name () == null) {
                /* No prebuilt binary for this arch — fall back to the browser. */
                yield open_rpc_download_page ();
                return;
            }

            rpc_download_btn.sensitive = false;
            string prev_subtitle = rpc_row.subtitle;
            var installer = new RpcInstaller ();
            installer.progress.connect ((received, total) => {
                if (total > 0) {
                    rpc_row.subtitle = "Downloading… %.0f%%".printf (
                        (double) received / (double) total * 100.0);
                } else {
                    rpc_row.subtitle = "Downloading… %.1f MB".printf (
                        received / 1048576.0);
                }
            });

            try {
                yield installer.download_latest ();
                /* Make sure the freshly installed managed binary is the one
                   Parla resolves on next start. */
                if (app_window.settings.rpc_server_source != RpcServerSource.AUTO) {
                    app_window.settings.save_rpc_server_source (RpcServerSource.AUTO);
                    sync_rpc_source_dropdown ();
                }
                app_window.show_toast ("RPC server installed. Restart to apply.");
            } catch (Error e) {
                rpc_row.subtitle = prev_subtitle;
                app_window.show_toast ("Download failed: " + e.message);
            } finally {
                rpc_download_btn.sensitive = true;
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

        private static void apply_accent_to_button (Gtk.ColorDialogButton btn,
                                                     string hex) {
            var rgba = Gdk.RGBA ();
            if (hex.length == 0 || !rgba.parse (hex)) {
                rgba.parse ("#3584e4");
            }
            btn.set_rgba (rgba);
        }

        private static void delete_parla_config () {
            var dir = Path.build_filename (
                Environment.get_user_config_dir (), "parla");
            FileUtils.unlink (Path.build_filename (dir, "settings.ini"));
            DirUtils.remove (dir);
        }
    }
}
