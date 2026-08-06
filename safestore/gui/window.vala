namespace SafeStore {

    public class Window : Adw.ApplicationWindow {

        private Settings settings;
        private CryfsController controller;

        private Adw.EntryRow vault_row;
        private Adw.EntryRow mount_row;
        private Adw.EntryRow binary_row;
        private Adw.ActionRow backend_row;
        private Adw.ActionRow state_row;
        private Gtk.Image state_icon;
        private Gtk.Spinner state_spinner;
        private Gtk.SpinButton idle_spin;
        private Gtk.Button create_button;
        private Gtk.Button unlock_button;
        private Gtk.Button lock_button;
        private Gtk.Button open_button;
        private Gtk.Button copy_button;
        private Gtk.TextBuffer log_buffer;
        private Adw.ToastOverlay toast_overlay;
        private bool backend_ready = false;
        private uint backend_check_generation = 0;

        public Window (Adw.Application application) {
            Object (
                application: application,
                title: "SafeStore",
                default_width: 760,
                default_height: 760
            );

            settings = new Settings ();
            controller = new CryfsController ();
            build_ui ();
            connect_signals ();
            sync_controls (controller.state, controller.detail);
            check_backend.begin ();
        }

        private void build_ui () {
            var header = new Adw.HeaderBar ();
            var title = new Adw.WindowTitle (
                "SafeStore",
                "Experimental CryFS vault manager"
            );
            header.title_widget = title;

            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (header);

            toast_overlay = new Adw.ToastOverlay ();
            toolbar.content = toast_overlay;
            content = toolbar;

            var page = new Gtk.Box (Gtk.Orientation.VERTICAL, 18);
            page.margin_top = 24;
            page.margin_bottom = 24;
            page.margin_start = 24;
            page.margin_end = 24;

            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 720;
            clamp.tightening_threshold = 560;
            clamp.child = page;

            var scroller = new Gtk.ScrolledWindow ();
            scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroller.child = clamp;
            toast_overlay.child = scroller;

            var intro = new Gtk.Label (
                "Create or unlock a local encrypted directory. SafeStore " +
                "never stores the vault password and is not connected to Parla."
            );
            intro.wrap = true;
            intro.xalign = 0;
            intro.add_css_class ("dim-label");
            page.append (intro);

            var status_group = new Adw.PreferencesGroup ();
            status_group.title = "Status";
            state_row = new Adw.ActionRow ();
            state_row.title = "Locked";
            state_row.subtitle = "Vault is locked";
            state_icon = new Gtk.Image.from_icon_name (
                "changes-prevent-symbolic");
            state_row.add_prefix (state_icon);
            state_spinner = new Gtk.Spinner ();
            state_row.add_suffix (state_spinner);
            status_group.add (state_row);

            backend_row = new Adw.ActionRow ();
            backend_row.title = "CryFS backend";
            backend_row.subtitle = "Checking…";
            var check_button = new Gtk.Button.from_icon_name (
                "view-refresh-symbolic");
            check_button.valign = Gtk.Align.CENTER;
            check_button.add_css_class ("flat");
            check_button.tooltip_text = "Check CryFS installation";
            check_button.clicked.connect (() => { check_backend.begin (); });
            backend_row.add_suffix (check_button);
            status_group.add (backend_row);
            page.append (status_group);

            var location_group = new Adw.PreferencesGroup ();
            location_group.title = "Locations";
            location_group.description =
                "The encrypted vault and plaintext mount must be separate folders.";

            vault_row = new Adw.EntryRow ();
            vault_row.title = "Encrypted vault folder";
            vault_row.text = settings.vault_path;
            add_folder_button (vault_row, true);
            location_group.add (vault_row);

            mount_row = new Adw.EntryRow ();
            mount_row.title = "Plaintext mount folder";
            mount_row.text = settings.mount_path;
            add_folder_button (mount_row, false);
            location_group.add (mount_row);

            binary_row = new Adw.EntryRow ();
            binary_row.title = "CryFS executable";
            binary_row.text = settings.cryfs_binary;
            var binary_button = new Gtk.Button.from_icon_name (
                "document-open-symbolic");
            binary_button.valign = Gtk.Align.CENTER;
            binary_button.add_css_class ("flat");
            binary_button.tooltip_text = "Choose CryFS executable";
            binary_button.clicked.connect (() => {
                choose_binary.begin ();
            });
            binary_row.add_suffix (binary_button);
            location_group.add (binary_row);

            var idle_row = new Adw.ActionRow ();
            idle_row.title = "Idle auto-lock";
            idle_row.subtitle = "0 disables it; CryFS measures filesystem inactivity";
            var adjustment = new Gtk.Adjustment (
                settings.idle_minutes, 0, 1440, 5, 30, 0);
            idle_spin = new Gtk.SpinButton (adjustment, 5, 0);
            idle_spin.valign = Gtk.Align.CENTER;
            idle_spin.tooltip_text = "Minutes";
            idle_row.add_suffix (idle_spin);
            location_group.add (idle_row);
            page.append (location_group);

            var actions_group = new Adw.PreferencesGroup ();
            actions_group.title = "Vault";
            var action_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            action_box.homogeneous = true;

            create_button = new Gtk.Button.with_label ("Create");
            create_button.add_css_class ("suggested-action");
            create_button.clicked.connect (() => { show_create_dialog (); });
            action_box.append (create_button);

            unlock_button = new Gtk.Button.with_label ("Unlock");
            unlock_button.add_css_class ("suggested-action");
            unlock_button.clicked.connect (() => { show_unlock_dialog (); });
            action_box.append (unlock_button);

            lock_button = new Gtk.Button.with_label ("Lock");
            lock_button.add_css_class ("destructive-action");
            lock_button.clicked.connect (() => { lock_vault.begin (); });
            action_box.append (lock_button);

            actions_group.add (action_box);

            var utility_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            utility_box.homogeneous = true;
            utility_box.margin_top = 8;

            open_button = new Gtk.Button.with_label ("Open Mount");
            open_button.clicked.connect (() => { open_mount.begin (); });
            utility_box.append (open_button);

            copy_button = new Gtk.Button.with_label ("Copy Accounts Path");
            copy_button.tooltip_text =
                "Copy the value to use for DC_ACCOUNTS_PATH";
            copy_button.clicked.connect (() => {
                get_clipboard ().set_text (
                    PathPolicy.normalize (mount_row.text));
                show_toast ("Mounted accounts path copied");
            });
            utility_box.append (copy_button);
            actions_group.add (utility_box);
            page.append (actions_group);

            var log_group = new Adw.PreferencesGroup ();
            log_group.title = "Activity";
            log_group.description =
                "Passwords are never written to this log.";

            log_buffer = new Gtk.TextBuffer (null);
            var log_view = new Gtk.TextView.with_buffer (log_buffer);
            log_view.editable = false;
            log_view.cursor_visible = false;
            log_view.monospace = true;
            log_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            log_view.left_margin = 10;
            log_view.right_margin = 10;
            log_view.top_margin = 10;
            log_view.bottom_margin = 10;

            var log_scroller = new Gtk.ScrolledWindow ();
            log_scroller.min_content_height = 180;
            log_scroller.has_frame = true;
            log_scroller.child = log_view;
            log_group.add (log_scroller);
            page.append (log_group);

            append_log (
                "SafeStore ready. Configure folders, then create or unlock a vault.");
        }

        private void connect_signals () {
            controller.output.connect ((line) => { append_log (line); });
            controller.state_changed.connect ((state, detail) => {
                sync_controls (state, detail);
            });
            binary_row.changed.connect (() => {
                backend_check_generation++;
                backend_ready = false;
                backend_row.subtitle = "Press refresh to check this executable";
                sync_controls (controller.state, controller.detail);
            });
            close_request.connect (() => {
                if (controller.process_active) {
                    show_toast ("Lock the vault before closing SafeStore");
                    return true;
                }
                return false;
            });
        }

        private void add_folder_button (Adw.EntryRow row, bool vault) {
            var button = new Gtk.Button.from_icon_name (
                "folder-open-symbolic");
            button.valign = Gtk.Align.CENTER;
            button.add_css_class ("flat");
            button.tooltip_text = "Choose folder";
            button.clicked.connect (() => {
                choose_folder.begin (row, vault);
            });
            row.add_suffix (button);
        }

        private async void choose_folder (Adw.EntryRow row, bool vault) {
            var dialog = new Gtk.FileDialog ();
            dialog.title = vault
                ? "Choose encrypted vault folder"
                : "Choose plaintext mount folder";
            dialog.modal = true;

            string current = PathPolicy.normalize (row.text);
            string initial = current;
            if (!FileUtils.test (initial, FileTest.IS_DIR)) {
                initial = Path.get_dirname (initial);
            }
            if (FileUtils.test (initial, FileTest.IS_DIR)) {
                dialog.initial_folder = File.new_for_path (initial);
            }

            try {
                File? folder = yield dialog.select_folder (this, null);
                string? path = folder != null ? folder.get_path () : null;
                if (path != null) row.text = path;
            } catch (Error error) {
                if (!is_dialog_dismissal (error)) show_error (error.message);
            }
        }

        private async void choose_binary () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Choose CryFS executable";
            dialog.modal = true;

            string current = binary_row.text.strip ();
            if (Path.is_absolute (current)
                    && FileUtils.test (current, FileTest.EXISTS)) {
                dialog.initial_file = File.new_for_path (current);
            }

            try {
                File? file = yield dialog.open (this, null);
                string? path = file != null ? file.get_path () : null;
                if (path != null) {
                    binary_row.text = path;
                    save_settings ();
                    check_backend.begin ();
                }
            } catch (Error error) {
                if (!is_dialog_dismissal (error)) show_error (error.message);
            }
        }

        private void show_create_dialog () {
            var dialog = password_dialog (
                "Create encrypted vault",
                "Choose a strong password of at least 12 characters. " +
                "SafeStore cannot recover a forgotten password.",
                true
            );
            dialog.present (this);
        }

        private void show_unlock_dialog () {
            var dialog = password_dialog (
                "Unlock encrypted vault",
                "Enter the password for the selected CryFS vault.",
                false
            );
            dialog.present (this);
        }

        private Adw.AlertDialog password_dialog (string title,
                                                 string body,
                                                 bool create) {
            var dialog = new Adw.AlertDialog (title, body);
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            var password = new Gtk.PasswordEntry ();
            password.placeholder_text = "Password";
            password.show_peek_icon = true;
            password.activates_default = true;
            box.append (password);

            Gtk.PasswordEntry? confirmation = null;
            if (create) {
                confirmation = new Gtk.PasswordEntry ();
                confirmation.placeholder_text = "Confirm password";
                confirmation.show_peek_icon = true;
                confirmation.activates_default = true;
                box.append (confirmation);
            }

            dialog.extra_child = box;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response (
                "continue", create ? "Create and Mount" : "Unlock");
            dialog.set_response_appearance (
                "continue", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "continue";
            dialog.close_response = "cancel";
            dialog.response.connect ((response) => {
                if (response != "continue") {
                    password.text = "";
                    if (confirmation != null) confirmation.text = "";
                    return;
                }

                string secret = password.text;
                string repeated = confirmation != null
                    ? confirmation.text : secret;
                password.text = "";
                if (confirmation != null) confirmation.text = "";

                if (secret.length == 0) {
                    show_error ("Password cannot be empty.");
                    return;
                }
                if (secret.contains ("\n") || secret.contains ("\r")) {
                    show_error ("Passwords cannot contain line breaks.");
                    return;
                }
                if (create && secret.char_count () < 12) {
                    show_error (
                        "Use at least 12 characters for a new vault password.");
                    return;
                }
                if (create && secret != repeated) {
                    show_error ("The passwords do not match.");
                    return;
                }
                mount_vault (secret, create);
            });
            return dialog;
        }

        private void mount_vault (string password, bool create) {
            try {
                save_settings ();
                controller.mount (
                    settings.cryfs_binary,
                    settings.vault_path,
                    settings.mount_path,
                    password,
                    settings.idle_minutes,
                    create
                );
            } catch (Error error) {
                append_log ("Error: " + error.message);
                show_error (error.message);
            }
            password = "";
        }

        private async void lock_vault () {
            try {
                yield controller.unmount (
                    settings.cryfs_binary,
                    settings.mount_path
                );
            } catch (Error error) {
                append_log ("Error: " + error.message);
                show_error (error.message);
            }
        }

        private async void check_backend () {
            save_settings ();
            uint generation = ++backend_check_generation;
            string binary = settings.cryfs_binary;
            backend_row.subtitle = "Checking…";
            try {
                string version = yield controller.backend_version (
                    binary);
                if (generation != backend_check_generation) return;
                backend_ready = is_supported_backend (version);
                backend_row.subtitle = backend_ready
                    ? version
                    : "Unsupported: %s (stable CryFS 1.x required)".printf (
                        version);
                append_log ("Backend: " + version);
            } catch (Error error) {
                if (generation != backend_check_generation) return;
                backend_ready = false;
                backend_row.subtitle =
                    "Unavailable — install CryFS or choose its executable";
                append_log ("CryFS check failed: " + error.message);
            }
            sync_controls (controller.state, controller.detail);
        }

        private async void open_mount () {
            try {
                string uri = File.new_for_path (
                    settings.mount_path).get_uri ();
                yield AppInfo.launch_default_for_uri_async (
                    uri, null, null);
            } catch (Error error) {
                show_error (error.message);
            }
        }

        private void save_settings () {
            settings.vault_path = PathPolicy.normalize (vault_row.text);
            settings.mount_path = PathPolicy.normalize (mount_row.text);
            settings.cryfs_binary = binary_row.text.strip ();
            settings.idle_minutes = idle_spin.get_value_as_int ();
            settings.save ();
        }

        private void sync_controls (StoreState state, string detail) {
            bool busy = state == StoreState.STARTING
                || state == StoreState.STOPPING;
            bool mounted = state == StoreState.MOUNTED;
            bool active = controller.process_active;

            state_spinner.spinning = busy;
            state_spinner.visible = busy;
            state_row.subtitle = detail;

            switch (state) {
            case StoreState.LOCKED:
                state_row.title = "Locked";
                state_icon.icon_name = "changes-prevent-symbolic";
                break;
            case StoreState.STARTING:
                state_row.title = "Unlocking";
                state_icon.icon_name = "changes-allow-symbolic";
                break;
            case StoreState.MOUNTED:
                state_row.title = "Mounted";
                state_icon.icon_name = "changes-allow-symbolic";
                break;
            case StoreState.STOPPING:
                state_row.title = "Locking";
                state_icon.icon_name = "changes-prevent-symbolic";
                break;
            case StoreState.ERROR:
                state_row.title = "Attention needed";
                state_icon.icon_name = "dialog-warning-symbolic";
                break;
            }

            create_button.sensitive = backend_ready && !busy && !active;
            unlock_button.sensitive = backend_ready && !busy && !active;
            lock_button.sensitive = active && !busy;
            open_button.sensitive = mounted;
            copy_button.sensitive = mounted;
            vault_row.sensitive = !busy && !active;
            mount_row.sensitive = !busy && !active;
            binary_row.sensitive = !busy && !active;
            idle_spin.sensitive = !busy && !active;
        }

        private void append_log (string line) {
            Gtk.TextIter end;
            log_buffer.get_end_iter (out end);
            string timestamp = new DateTime.now_local ().format ("%H:%M:%S");
            log_buffer.insert (ref end, "[%s] %s\n".printf (timestamp, line), -1);
        }

        private void show_toast (string message) {
            toast_overlay.add_toast (new Adw.Toast (message));
        }

        private void show_error (string message) {
            var dialog = new Adw.AlertDialog ("SafeStore", message);
            dialog.add_response ("ok", "OK");
            dialog.present (this);
        }

        private static bool is_dialog_dismissal (Error error) {
            return error.matches (Gtk.DialogError.quark (),
                                  Gtk.DialogError.DISMISSED)
                || error.matches (Gtk.DialogError.quark (),
                                  Gtk.DialogError.CANCELLED)
                || error.matches (IOError.quark (), IOError.CANCELLED);
        }

        private static bool is_supported_backend (string version) {
            string clean = version.strip ();
            return clean.contains ("CryFS Version 1.")
                || clean.ascii_down ().has_prefix ("cryfs 1.");
        }
    }
}
