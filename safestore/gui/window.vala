namespace SafeStore {

    public class Window : Adw.ApplicationWindow {

        private Settings settings;
        private CryfsController controller;

        private Adw.ActionRow vault_row;
        private Adw.ActionRow mount_row;
        private Adw.EntryRow binary_row;
        private Adw.EntryRow zip_binary_row;
        private Adw.EntryRow unzip_binary_row;
        private Adw.ComboRow backend_combo;
        private Gtk.Switch shred_switch;
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
        private bool zip_unlocked = false;
        private bool zip_operation_active = false;

        public Window (Adw.Application application) {
            Object (
                application: application,
                title: "SafeStore",
                default_width: 760,
                default_height: 760
            );

            settings = new Settings ();
            controller = new CryfsController ();
            zip_unlocked = settings.backend == "zip"
                && ZipBackend.is_unlocked (settings);
            build_ui ();
            connect_signals ();
            sync_controls (controller.state, controller.detail);
            check_backend.begin ();
        }

        private void build_ui () {
            var header = new Adw.HeaderBar ();
            var title = new Adw.WindowTitle (
                "SafeStore",
                "Experimental encrypted account storage"
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
                "Create or unlock the encrypted Delta Chat accounts vault. " +
                "SafeStore never stores the vault password."
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
            backend_row.title = "Selected backend";
            backend_row.subtitle = "Checking…";
            var check_button = new Gtk.Button.from_icon_name (
                "view-refresh-symbolic");
            check_button.valign = Gtk.Align.CENTER;
            check_button.add_css_class ("flat");
            check_button.tooltip_text = "Check encryption backends";
            check_button.clicked.connect (() => { check_backend.begin (); });
            backend_row.add_suffix (check_button);
            status_group.add (backend_row);
            page.append (status_group);

            var backend_group = new Adw.PreferencesGroup ();
            backend_group.title = "Encryption backend";
            backend_group.description =
                "CryFS is strongly preferred. ZIP is a weaker compatibility "
                + "option that exposes file names and extracts plaintext while unlocked.";
            backend_combo = new Adw.ComboRow ();
            backend_combo.title = "Backend";
            backend_combo.model = new Gtk.StringList ({
                "CryFS (recommended)", "ZIP archive (weaker)"
            });
            backend_combo.selected = settings.backend == "zip" ? 1 : 0;
            backend_group.add (backend_combo);
            page.append (backend_group);

            var location_group = new Adw.PreferencesGroup ();
            location_group.title = "Locations";
            location_group.description = (
                "Fixed by the Delta Chat accounts path (%s): the decrypted "
                + "view mounts on the accounts folder and the vault sits "
                + "beside it.").printf (AccountsPath.source ());

            vault_row = new Adw.ActionRow ();
            vault_row.title = "Encrypted vault folder";
            vault_row.subtitle = settings.vault_path;
            vault_row.subtitle_selectable = true;
            vault_row.add_css_class ("property");
            location_group.add (vault_row);

            mount_row = new Adw.ActionRow ();
            mount_row.title = "Decrypted accounts folder";
            mount_row.subtitle = settings.mount_path;
            mount_row.subtitle_selectable = true;
            mount_row.add_css_class ("property");
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

            zip_binary_row = new Adw.EntryRow ();
            zip_binary_row.title = "zip executable";
            zip_binary_row.text = settings.zip_binary;
            location_group.add (zip_binary_row);

            unzip_binary_row = new Adw.EntryRow ();
            unzip_binary_row.title = "unzip executable";
            unzip_binary_row.text = settings.unzip_binary;
            location_group.add (unzip_binary_row);

            var shred_row = new Adw.ActionRow ();
            shred_row.title = "Overwrite plaintext when locking";
            shred_row.subtitle =
                "Best effort only; SSDs, snapshots, journals, and backups may retain data";
            shred_switch = new Gtk.Switch ();
            shred_switch.valign = Gtk.Align.CENTER;
            shred_switch.active = settings.secure_delete;
            shred_row.add_suffix (shred_switch);
            shred_row.activatable_widget = shred_switch;
            location_group.add (shred_row);

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
                    PathPolicy.normalize (settings.mount_path));
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
                "SafeStore ready. Select a backend, then create or unlock a vault.");
            sync_backend_fields ();
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
            zip_binary_row.changed.connect (() => {
                backend_check_generation++;
                backend_ready = false;
                backend_row.subtitle = "Press refresh to check the ZIP tools";
                sync_controls (controller.state, controller.detail);
            });
            unzip_binary_row.changed.connect (() => {
                backend_check_generation++;
                backend_ready = false;
                backend_row.subtitle = "Press refresh to check the ZIP tools";
                sync_controls (controller.state, controller.detail);
            });
            backend_combo.notify["selected"].connect (() => {
                if (controller.process_active || zip_unlocked
                        || zip_operation_active) return;
                settings.backend = backend_combo.selected == 1 ? "zip" : "cryfs";
                save_settings ();
                sync_backend_fields ();
                check_backend.begin ();
            });
            close_request.connect (() => {
                if (controller.process_active || zip_unlocked
                        || zip_operation_active) {
                    show_toast ("Lock the vault before closing SafeStore");
                    return true;
                }
                return false;
            });
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
                "Enter the password for the selected encrypted vault.",
                false
            );
            dialog.present (this);
        }

        private Adw.AlertDialog password_dialog (string title,
                                                 string body,
                                                 bool create,
                                                 bool locking = false) {
            var dialog = new Adw.AlertDialog (title, body);
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            var password = new Gtk.PasswordEntry ();
            password.placeholder_text = "Password";
            password.show_peek_icon = true;
            password.activates_default = true;
            box.append (password);

            Gtk.PasswordEntry? confirmation = null;
            if (create || locking) {
                confirmation = new Gtk.PasswordEntry ();
                confirmation.placeholder_text = create
                    ? "Confirm password" : "Confirm archive password";
                confirmation.show_peek_icon = true;
                confirmation.activates_default = true;
                box.append (confirmation);
            }

            dialog.extra_child = box;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response (
                "continue", create ? "Create and Unlock"
                    : (locking ? "Lock" : "Unlock"));
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
                if (settings.backend == "zip") {
                    for (int i = 0; i < secret.length; i++) {
                        uint8 byte = secret.data[i];
                        if (byte < 0x20 || byte == 0x7f) {
                            show_error (
                                "ZIP passwords cannot contain control characters.");
                            return;
                        }
                    }
                }
                if (create && secret.char_count () < 12) {
                    show_error (
                        "Use at least 12 characters for a new vault password.");
                    return;
                }
                if ((create || locking) && secret != repeated) {
                    show_error ("The passwords do not match.");
                    return;
                }
                if (locking) lock_zip (secret);
                else mount_vault (secret, create);
            });
            return dialog;
        }

        private void mount_vault (string password, bool create) {
            try {
                save_settings ();
                if (settings.backend == "zip") {
                    start_zip_unlock (password, create);
                } else {
                    controller.mount (
                        settings.cryfs_binary,
                        settings.vault_path,
                        settings.mount_path,
                        password,
                        settings.idle_minutes,
                        create
                    );
                }
            } catch (Error error) {
                append_log ("Error: " + error.message);
                show_error (error.message);
            }
            password = "";
        }

        private async void lock_vault () {
            if (settings.backend == "zip") {
                var dialog = password_dialog (
                    "Lock ZIP vault",
                    "The accounts will be archived before plaintext is removed. "
                    + "Close Parla first so all database writes are complete.",
                    false,
                    true);
                dialog.present (this);
                return;
            }
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

        private void lock_zip (string password) {
            save_settings ();
            zip_operation_active = true;
            sync_controls (StoreState.STOPPING, "Archiving ZIP vault…");
            string secret = password;
            new Thread<void*> ("safestore-zip-lock", () => {
                string? failure = null;
                try {
                    ZipBackend.lock (settings, secret);
                } catch (Error error) {
                    failure = error.message;
                }
                secret = "";
                Idle.add (() => {
                    zip_operation_active = false;
                    if (failure == null) {
                        zip_unlocked = false;
                        append_log (
                            "ZIP archive replaced successfully; plaintext accounts removed.");
                        if (settings.secure_delete) {
                            append_log (
                                "Plaintext files received best-effort overwrite removal.");
                        }
                        sync_controls (StoreState.LOCKED, "ZIP vault is locked");
                    } else {
                        append_log ("Error: " + failure);
                        sync_controls (StoreState.ERROR,
                            "ZIP lock failed; plaintext may still be present");
                        show_error (failure);
                    }
                    return Source.REMOVE;
                });
                return null;
            });
            password = "";
        }

        private void start_zip_unlock (string password, bool create) {
            zip_operation_active = true;
            sync_controls (StoreState.STARTING,
                create ? "Creating ZIP vault…" : "Extracting ZIP vault…");
            string secret = password;
            new Thread<void*> ("safestore-zip-unlock", () => {
                string? failure = null;
                try {
                    if (create) ZipBackend.create (settings, secret);
                    else ZipBackend.unlock (settings, secret);
                } catch (Error error) {
                    failure = error.message;
                }
                secret = "";
                Idle.add (() => {
                    zip_operation_active = false;
                    if (failure == null) {
                        zip_unlocked = true;
                        append_log (create
                            ? "ZIP vault created; plaintext accounts are exposed while unlocked."
                            : "ZIP vault extracted; plaintext accounts are exposed while unlocked.");
                        sync_controls (StoreState.MOUNTED,
                            "ZIP vault unlocked; plaintext is exposed");
                    } else {
                        append_log ("Error: " + failure);
                        sync_controls (StoreState.ERROR,
                            "ZIP operation failed; accounts remain locked");
                        show_error (failure);
                    }
                    return Source.REMOVE;
                });
                return null;
            });
        }

        private async void check_backend () {
            save_settings ();
            uint generation = ++backend_check_generation;
            backend_row.subtitle = "Checking…";
            try {
                BackendInfo info = Backends.selected (settings);
                if (generation != backend_check_generation) return;
                backend_ready = info.available;
                backend_row.subtitle = info.status;
                append_log ("Backend %s: %s".printf (info.id, info.status));
                append_log ("Protection: " + info.protection);
            } catch (Error error) {
                if (generation != backend_check_generation) return;
                backend_ready = false;
                backend_row.subtitle = "Unavailable — " + error.message;
                append_log ("Backend check failed: " + error.message);
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
            settings.cryfs_binary = binary_row.text.strip ();
            settings.zip_binary = zip_binary_row.text.strip ();
            settings.unzip_binary = unzip_binary_row.text.strip ();
            settings.secure_delete = shred_switch.active;
            settings.idle_minutes = idle_spin.get_value_as_int ();
            settings.save ();
        }

        private void sync_controls (StoreState state, string detail) {
            if (zip_unlocked && state == StoreState.LOCKED) {
                state = StoreState.MOUNTED;
                detail = "ZIP vault unlocked; plaintext is exposed";
            }
            bool busy = state == StoreState.STARTING
                || state == StoreState.STOPPING;
            bool mounted = state == StoreState.MOUNTED || zip_unlocked;
            bool active = controller.process_active || zip_unlocked
                || zip_operation_active;

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
            binary_row.sensitive = !busy && !active;
            zip_binary_row.sensitive = !busy && !active;
            unzip_binary_row.sensitive = !busy && !active;
            backend_combo.sensitive = !busy && !active;
            shred_switch.sensitive = settings.backend == "zip" && !busy && !active;
            idle_spin.sensitive = settings.backend != "zip"
                && !busy && !active;
        }

        private void sync_backend_fields () {
            bool zip = settings.backend == "zip";
            vault_row.subtitle = settings.vault_path;
            vault_row.title = zip ? "Encrypted ZIP archive"
                                  : "Encrypted vault folder";
            mount_row.title = zip ? "Plaintext accounts folder"
                                  : "Decrypted accounts folder";
            binary_row.visible = !zip;
            zip_binary_row.visible = zip;
            unzip_binary_row.visible = zip;
            idle_spin.sensitive = !zip;
            backend_row.title = zip ? "ZIP archive backend (weaker)"
                                    : "CryFS backend";
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

    }
}
