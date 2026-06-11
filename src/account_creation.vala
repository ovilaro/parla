namespace Dc {

    /**
     * Account-creation flows. Hosts the dialog(s) that turn the four
     * "Add Account" entry points into concrete RPC calls.
     *
     * Currently implemented:
     *   - Create new profile (CreateProfileDialog) — chatmail relay
     *   - Add as secondary device (ReceiveBackupDialog)
     *   - Use invitation code (InvitationCodeProfileDialog)
     *
     * Stubs for future work:
     *   - Use classic email address (lives in window.vala for now)
     */

    private static Gtk.Box account_setup_content () {
        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        content.margin_start = content.margin_end = 18;
        content.margin_top = 12;
        content.margin_bottom = 18;
        return content;
    }

    private static Gtk.Label account_setup_intro (string text) {
        var intro = new Gtk.Label (text);
        intro.wrap = true;
        intro.xalign = 0;
        intro.add_css_class ("dim-label");
        return intro;
    }

    private static Gtk.Label account_setup_heading (string text) {
        var label = new Gtk.Label (text);
        label.add_css_class ("heading");
        label.xalign = 0;
        return label;
    }

    private static Gtk.Box account_setup_action_row (bool with_margin = true) {
        var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        row.halign = Gtk.Align.END;
        if (with_margin) row.margin_top = 6;
        return row;
    }

    private static Gtk.Stack account_setup_stack (Gtk.Widget input_page,
                                                   Gtk.Widget progress_page) {
        var stack = new Gtk.Stack ();
        stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
        stack.transition_duration = 180;
        stack.vexpand = true;
        stack.add_named (input_page, "input");
        stack.add_named (progress_page, "progress");
        return stack;
    }

    private static Gtk.Box account_setup_shell (Gtk.Stack stack) {
        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        box.append (new Adw.HeaderBar ());
        box.append (stack);
        return box;
    }

    private static void disconnect_progress_handler (EventHandler events,
                                                     ref ulong handler_id) {
        if (handler_id == 0) return;
        events.disconnect (handler_id);
        handler_id = 0;
    }

    private static void stop_ongoing_account (RpcClient rpc, int account_id) {
        if (account_id <= 0) return;
        rpc.stop_ongoing_process.begin (account_id, (obj, res) => {
            try { rpc.stop_ongoing_process.end (res); }
            catch (Error e) { /* ignore */ }
        });
    }

    private static async void cleanup_pending_account (RpcClient rpc,
                                                       int account_id,
                                                       bool stop_first) {
        if (account_id <= 0) return;
        if (stop_first) {
            try { yield rpc.stop_ongoing_process (account_id); }
            catch (Error e) { /* ignore */ }
        }
        try { yield rpc.remove_account (account_id); }
        catch (Error e) { /* ignore */ }
    }

    private class AccountProgressPage : Gtk.Box {
        private Gtk.ProgressBar progress_bar;
        private Gtk.Label progress_label;
        private Gtk.Label status_label;

        public signal void cancel_requested ();

        public AccountProgressPage (string initial_status,
                                    bool wrap_status = false) {
            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 12
            );
            margin_start = margin_end = 18;
            margin_top = 12;
            margin_bottom = 18;
            valign = Gtk.Align.CENTER;

            status_label = new Gtk.Label (initial_status);
            status_label.xalign = 0;
            status_label.wrap = wrap_status;
            append (status_label);

            progress_bar = new Gtk.ProgressBar ();
            progress_bar.fraction = 0.0;
            progress_bar.show_text = false;
            append (progress_bar);

            progress_label = new Gtk.Label ("0 %");
            progress_label.xalign = 0;
            progress_label.add_css_class ("dim-label");
            append (progress_label);

            var actions = account_setup_action_row ();
            var cancel_btn = new Gtk.Button.with_label ("Cancel");
            cancel_btn.add_css_class ("destructive-action");
            cancel_btn.clicked.connect (() => { cancel_requested (); });
            actions.append (cancel_btn);
            append (actions);
        }

        public void set_status (string status) {
            status_label.label = status;
        }

        public void set_permille (int progress, string? comment = null,
                                  string? active_status = null) {
            if (progress == 0) {
                set_status (comment ?? "Failed");
                return;
            }

            double fraction = ((double) progress) / 1000.0;
            if (fraction > 1.0) fraction = 1.0;
            progress_bar.fraction = fraction;
            progress_label.label = "%d %%".printf ((int) (fraction * 100));

            if (comment != null && comment.length > 0) {
                set_status (comment);
            } else if (progress >= 1000) {
                set_status ("Finishing…");
            } else if (active_status != null) {
                set_status (active_status);
            }
        }
    }

    /**
     * Creates a fresh chatmail profile on the relay chosen by the user.
     * Server-side picks an address, returns credentials, and the rpc
     * server configures the account end-to-end. ConfigureProgress events
     * drive the progress bar.
     */
    public class CreateProfileDialog : Adw.Dialog {

        public signal void account_created (int new_account_id);

        private RpcClient rpc;
        private EventHandler events;

        private Gtk.Stack stack;
        private Gtk.Entry name_entry;
        private RelayPicker relay_picker;
        private Gtk.Button create_btn;
        private AccountProgressPage progress_page;

        private int new_account_id = 0;
        private bool create_running = false;
        private bool create_finished = false;
        private bool cancelled = false;
        private ulong progress_handler_id = 0;

        public CreateProfileDialog (RpcClient rpc, EventHandler events) {
            this.rpc = rpc;
            this.events = events;

            this.title = "Create New Profile";
            this.content_width = 480;
            this.can_close = true;

            stack = account_setup_stack (
                build_input_page (), build_progress_page ());
            this.child = account_setup_shell (stack);

            install_escape_close (this);
            this.closed.connect (on_dialog_closed);
        }

        /* ---- UI ---- */

        private Gtk.Widget build_input_page () {
            var content = account_setup_content ();
            content.append (account_setup_intro (
                "Pick a chatmail relay or enter a custom server. The server will assign you an email " +
                "address and password automatically — encryption keys are " +
                "generated on this device."));

            content.append (account_setup_heading ("Display Name"));

            name_entry = new Gtk.Entry ();
            name_entry.placeholder_text = "Your name";
            name_entry.activates_default = true;
            content.append (name_entry);

            content.append (account_setup_heading ("Server"));

            relay_picker = new RelayPicker ();
            content.append (relay_picker);

            var hint = new Gtk.Label (null);
            hint.use_markup = true;
            hint.xalign = 0;
            hint.wrap = true;
            hint.add_css_class ("dim-label");
            hint.add_css_class ("caption");
            hint.label = "See <a href=\"https://chatmail.at/relays\">" +
                "chatmail.at/relays</a> for the full list.";
            content.append (hint);

            var row = account_setup_action_row ();
            create_btn = new Gtk.Button.with_label ("Create Profile");
            create_btn.add_css_class ("suggested-action");
            create_btn.clicked.connect (() => { do_create.begin (); });
            row.append (create_btn);
            this.default_widget = create_btn;
            content.append (row);

            return content;
        }

        private Gtk.Widget build_progress_page () {
            progress_page = new AccountProgressPage ("Contacting server…");
            progress_page.cancel_requested.connect (cancel_create);
            return progress_page;
        }

        /* ---- Flow ---- */

        private async void do_create () {
            if (create_running) return;

            string display_name = name_entry.text.strip ();
            string domain = relay_picker.get_selected_domain ();
            string qr_link = relay_picker.get_chatmail_qr ();

            create_running = true;
            stack.visible_child_name = "progress";
            progress_page.set_status ("Creating profile on %s…".printf (domain));

            progress_handler_id = events.configure_progress.connect (
                on_configure_progress);

            try {
                new_account_id = yield rpc.add_account ();
            } catch (Error e) {
                cleanup_signal ();
                create_running = false;
                if (!cancelled) {
                    show_error (this, "Failed to create account: " + e.message);
                    this.close ();
                }
                return;
            }

            if (cancelled) {
                cleanup_signal ();
                create_running = false;
                return;
            }

            if (display_name.length > 0) {
                try {
                    yield rpc.batch_set_config ("displayname", display_name,
                                                  new_account_id);
                } catch (Error e) {
                    /* non-fatal — just continue */
                }
            }

            if (cancelled) {
                cleanup_signal ();
                create_running = false;
                return;
            }

            try {
                yield rpc.add_transport_from_qr (new_account_id, qr_link);
            } catch (Error e) {
                cleanup_signal ();
                create_running = false;
                if (cancelled) return;
                int aid = new_account_id;
                new_account_id = 0;
                yield cleanup_pending_account (rpc, aid, false);
                show_error (this, "Profile creation failed: " + e.message);
                this.close ();
                return;
            }

            cleanup_signal ();
            create_running = false;
            if (cancelled) return;
            create_finished = true;
            int created = new_account_id;
            new_account_id = 0;
            account_created (created);
            this.close ();
        }

        private void on_configure_progress (int ctx, int progress,
                                              string? comment) {
            if (ctx != new_account_id) return;
            progress_page.set_permille (progress, comment);
        }

        private void cleanup_signal () {
            disconnect_progress_handler (events, ref progress_handler_id);
        }

        private void cancel_create () {
            if (!create_running) {
                this.close ();
                return;
            }
            cancelled = true;
            /* Close the dialog immediately so the user gets feedback.
               The in-flight RPC may be inside a network retry loop and take
               many seconds to return — on_dialog_closed handles cleanup. */
            this.close ();
        }

        private void on_dialog_closed () {
            cleanup_signal ();
            if (!create_finished && new_account_id > 0) {
                int aid = new_account_id;
                new_account_id = 0;
                cleanup_pending_account.begin (rpc, aid, true);
            }
        }
    }

    /**
     * Creates a profile from a pasted Delta Chat invitation/account link.
     *
     * DCACCOUNT/DCLOGIN links configure the new profile directly using the
     * linked server credentials. Secure-join invitation links first create a
     * default chatmail profile and then accept the invite on the new profile,
     * matching Delta Chat Desktop's instant-onboarding flow.
     */
    public class InvitationCodeProfileDialog : Adw.Dialog {

        public signal void account_created (int new_account_id, int chat_id);

        private RpcClient rpc;
        private EventHandler events;

        private Gtk.Stack stack;
        private Gtk.Entry invite_entry;
        private Gtk.Button start_btn;
        private AccountProgressPage progress_page;

        private int new_account_id = 0;
        private bool create_running = false;
        private bool create_finished = false;
        private ulong progress_handler_id = 0;

        public InvitationCodeProfileDialog (RpcClient rpc, EventHandler events) {
            this.rpc = rpc;
            this.events = events;

            this.title = "Use Invitation Code";
            this.content_width = 480;
            this.can_close = true;

            stack = account_setup_stack (
                build_input_page (), build_progress_page ());
            this.child = account_setup_shell (stack);

            install_escape_close (this);
            this.closed.connect (on_dialog_closed);
        }

        private Gtk.Widget build_input_page () {
            var content = account_setup_content ();
            content.append (account_setup_intro (
                "Paste a Delta Chat account or invitation link. Account links " +
                "use the linked server; contact and group invites create a new " +
                "chatmail profile first."));

            invite_entry = new Gtk.Entry ();
            invite_entry.placeholder_text = "dcaccount:example.org or https://i.delta.chat/#...";
            invite_entry.input_purpose = Gtk.InputPurpose.URL;
            invite_entry.hexpand = true;
            invite_entry.activates_default = true;
            invite_entry.changed.connect (update_start_sensitivity);
            content.append (invite_entry);

            var row = account_setup_action_row (false);
            start_btn = new Gtk.Button.with_label ("Create Profile");
            start_btn.add_css_class ("suggested-action");
            start_btn.sensitive = false;
            start_btn.clicked.connect (() => { start_create.begin (); });
            row.append (start_btn);

            this.default_widget = start_btn;
            content.append (row);

            return content;
        }

        private Gtk.Widget build_progress_page () {
            progress_page = new AccountProgressPage ("Checking invitation…", true);
            progress_page.cancel_requested.connect (cancel_create);
            return progress_page;
        }

        private void update_start_sensitivity () {
            start_btn.sensitive = invite_entry.text.strip ().length > 0;
        }

        private async void start_create () {
            if (create_running) return;

            string invite_link = invite_entry.text.strip ();
            if (invite_link.length == 0) return;

            create_running = true;
            stack.visible_child_name = "progress";
            progress_page.set_status ("Checking invitation…");

            progress_handler_id = events.configure_progress.connect (
                on_configure_progress);

            try {
                new_account_id = yield rpc.add_account ();
            } catch (Error e) {
                cleanup_signal ();
                create_running = false;
                show_error (this, "Failed to create account: " + e.message);
                this.close ();
                return;
            }

            Json.Object? qr = null;
            try {
                qr = yield rpc.check_qr (new_account_id, invite_link);
            } catch (Error e) {
                yield fail_new_account ("Invitation code failed: " + e.message);
                return;
            }

            if (qr == null || !qr.has_member ("kind")) {
                yield fail_new_account ("This is not a valid Delta Chat invitation code.");
                return;
            }

            string kind = qr.get_string_member ("kind");
            int chat_id = 0;

            if (kind == "account" || kind == "login") {
                progress_page.set_status ("Creating profile…");
                try {
                    yield rpc.add_transport_from_qr (new_account_id, invite_link);
                } catch (Error e) {
                    yield fail_new_account ("Profile creation failed: " + e.message);
                    return;
                }
            } else if (kind == "askVerifyContact" ||
                       kind == "askVerifyGroup" ||
                       kind == "askJoinBroadcast") {
                progress_page.set_status ("Creating profile…");
                try {
                    yield rpc.add_transport_from_qr (
                        new_account_id,
                        build_chatmail_qr (CHATMAIL_RELAYS[0].domain));
                    progress_page.set_status ("Accepting invitation…");
                    chat_id = yield rpc.secure_join (new_account_id, invite_link);
                } catch (Error e) {
                    yield fail_new_account ("Invitation failed: " + e.message);
                    return;
                }
            } else {
                yield fail_new_account (
                    "This code cannot be used to create a profile.");
                return;
            }

            cleanup_signal ();
            create_finished = true;
            create_running = false;
            int created = new_account_id;
            new_account_id = 0;
            account_created (created, chat_id);
            this.close ();
        }

        private async void fail_new_account (string message) {
            cleanup_signal ();
            create_running = false;
            if (new_account_id > 0) {
                int aid = new_account_id;
                new_account_id = 0;
                yield cleanup_pending_account (rpc, aid, true);
            }
            show_error (this, message);
            this.close ();
        }

        private void on_configure_progress (int ctx, int progress,
                                              string? comment) {
            if (ctx != new_account_id) return;
            progress_page.set_permille (progress, comment);
        }

        private void cleanup_signal () {
            disconnect_progress_handler (events, ref progress_handler_id);
        }

        private void cancel_create () {
            if (!create_running) {
                this.close ();
                return;
            }
            if (new_account_id > 0) {
                stop_ongoing_account (rpc, new_account_id);
            }
        }

        private void on_dialog_closed () {
            cleanup_signal ();
            if (!create_finished && new_account_id > 0) {
                int aid = new_account_id;
                new_account_id = 0;
                cleanup_pending_account.begin (rpc, aid, true);
            }
        }
    }

    /**
     * Imports a profile from another device using the dcbackup token shown
     * by the source device. The user pastes the token into the entry; we
     * call get_backup() and stream ImexProgress to a progress bar. Cancel
     * stops the ongoing process and removes the half-imported account.
     *
     * On success the new account_id is reported via account_imported.
     */
    public class ReceiveBackupDialog : Adw.Dialog {

        public signal void account_imported (int new_account_id);

        private RpcClient rpc;
        private EventHandler events;

        private Gtk.Stack stack;
        private Gtk.Entry url_entry;
        private Gtk.Button start_btn;
        private AccountProgressPage progress_page;

        private int new_account_id = 0;
        private bool import_running = false;
        private bool import_finished = false;
        private ulong progress_handler_id = 0;

        public ReceiveBackupDialog (RpcClient rpc, EventHandler events) {
            this.rpc = rpc;
            this.events = events;

            this.title = "Add as Secondary Device";
            this.content_width = 480;
            this.can_close = true;

            stack = account_setup_stack (
                build_input_page (), build_progress_page ());
            this.child = account_setup_shell (stack);

            install_escape_close (this);
            this.closed.connect (on_dialog_closed);
        }

        /* ---- UI ---- */

        private Gtk.Widget build_input_page () {
            var content = account_setup_content ();
            content.append (account_setup_intro (
                "On your existing device, open Settings → " +
                "“Add Second Device” and copy the setup code shown there. " +
                "Paste it below."));

            url_entry = new Gtk.Entry ();
            url_entry.placeholder_text = "DCBACKUP2:…";
            url_entry.hexpand = true;
            url_entry.activates_default = true;
            url_entry.changed.connect (update_start_sensitivity);
            content.append (url_entry);

            var row = account_setup_action_row (false);
            start_btn = new Gtk.Button.with_label ("Start Import");
            start_btn.add_css_class ("suggested-action");
            start_btn.sensitive = false;
            start_btn.clicked.connect (() => { start_import.begin (); });
            row.append (start_btn);

            this.default_widget = start_btn;
            content.append (row);

            return content;
        }

        private Gtk.Widget build_progress_page () {
            progress_page = new AccountProgressPage ("Connecting…");
            progress_page.cancel_requested.connect (cancel_import);
            return progress_page;
        }

        /* ---- Helpers ---- */

        private void update_start_sensitivity () {
            string t = url_entry.text.strip ();
            start_btn.sensitive = t.length > 0;
        }

        /* ---- Import flow ---- */

        private async void start_import () {
            if (import_running) return;

            string qr = url_entry.text.strip ();
            if (qr.length == 0) return;

            import_running = true;
            stack.visible_child_name = "progress";

            /* Subscribe to ImexProgress for the new account */
            progress_handler_id = events.imex_progress.connect (on_imex_progress);

            try {
                new_account_id = yield rpc.add_account ();
            } catch (Error e) {
                cleanup_signal ();
                import_running = false;
                show_error (this, "Failed to create account: " + e.message);
                this.close ();
                return;
            }

            try {
                yield rpc.get_backup (new_account_id, qr);
            } catch (Error e) {
                cleanup_signal ();
                import_running = false;
                /* Drop the half-imported account so the user can retry */
                if (new_account_id > 0) {
                    yield cleanup_pending_account (rpc, new_account_id, false);
                    new_account_id = 0;
                }
                show_error (this, "Import failed: " + e.message);
                this.close ();
                return;
            }

            /* Success */
            cleanup_signal ();
            import_finished = true;
            import_running = false;
            int imported = new_account_id;
            new_account_id = 0; /* prevent cleanup from removing it */
            account_imported (imported);
            this.close ();
        }

        private void on_imex_progress (int ctx, int progress) {
            if (ctx != new_account_id) return;
            /* progress: 0=error, 1-999=permille, 1000=done */
            progress_page.set_permille (progress, null, "Transferring…");
        }

        private void cleanup_signal () {
            disconnect_progress_handler (events, ref progress_handler_id);
        }

        private void cancel_import () {
            if (!import_running) {
                this.close ();
                return;
            }
            if (new_account_id > 0) {
                stop_ongoing_account (rpc, new_account_id);
            }
            /* The pending get_backup() will return with an error and
               the cleanup path in start_import() will remove the account. */
        }

        private void on_dialog_closed () {
            cleanup_signal ();
            /* If user dismissed mid-flight without success, clean up. */
            if (!import_finished && new_account_id > 0) {
                int aid = new_account_id;
                new_account_id = 0;
                cleanup_pending_account.begin (rpc, aid, true);
            }
        }
    }
}
