namespace Dc {

    public class ProfileDialog : Adw.Dialog {

        private RpcClient rpc;
        private int account_id;
        private Adw.Avatar avatar_widget;
        private Gtk.Entry name_entry;
        private Gtk.Entry status_entry;
        private Gtk.Label email_label;
        private Gtk.Label connectivity_status_label;
        private Gtk.Label storage_summary_label;
        private Gtk.ProgressBar storage_progress;
        private string? avatar_path = null;
        private bool avatar_changed = false;

        public signal void profile_updated ();
        public signal void account_deleted (int acct_id);

        public ProfileDialog (RpcClient rpc, int acct_id = 0) {
            this.rpc = rpc;
            this.account_id = acct_id > 0 ? acct_id : rpc.account_id;
            this.title = "My Profile";
            this.content_width = 420;
            this.content_height = 560;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var header = new Adw.HeaderBar ();
            var save_btn = new Gtk.Button.with_label ("Save");
            save_btn.add_css_class ("suggested-action");
            save_btn.clicked.connect (() => {
                do_save.begin ();
            });
            header.pack_end (save_btn);
            box.append (header);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_start = 16;
            content.margin_end = 16;
            content.margin_top = 12;
            content.margin_bottom = 16;

            /* Avatar */
            avatar_widget = new Adw.Avatar (96, "", true);
            avatar_widget.halign = Gtk.Align.CENTER;
            content.append (avatar_widget);

            var avatar_btn = new Gtk.Button.with_label ("Change Avatar");
            avatar_btn.halign = Gtk.Align.CENTER;
            avatar_btn.add_css_class ("flat");
            avatar_btn.clicked.connect (() => {
                pick_avatar.begin ();
            });
            content.append (avatar_btn);

            content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            /* Display name */
            var name_lbl = new Gtk.Label ("Display Name");
            name_lbl.add_css_class ("heading");
            name_lbl.halign = Gtk.Align.START;
            content.append (name_lbl);

            name_entry = new Gtk.Entry ();
            name_entry.placeholder_text = "Your name";
            name_entry.changed.connect (() => {
                avatar_widget.text = name_entry.text.length > 0
                    ? name_entry.text : "";
            });
            content.append (name_entry);

            /* Status */
            var status_lbl = new Gtk.Label ("Status");
            status_lbl.add_css_class ("heading");
            status_lbl.halign = Gtk.Align.START;
            content.append (status_lbl);

            status_entry = new Gtk.Entry ();
            status_entry.placeholder_text = "Your status message";
            content.append (status_entry);

            /* Email (read-only) */
            var email_lbl = new Gtk.Label ("Email");
            email_lbl.add_css_class ("heading");
            email_lbl.halign = Gtk.Align.START;
            content.append (email_lbl);

            email_label = new Gtk.Label ("");
            email_label.halign = Gtk.Align.START;
            email_label.add_css_class ("dim-label");
            email_label.selectable = true;
            content.append (email_label);

            content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            content.append (build_connectivity_storage_section ());

            content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var invite_code_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            invite_code_box.margin_top = 4;

            var invite_code_btn = new Gtk.Button.with_label ("Invite Code");
            invite_code_btn.tooltip_text = "Show a contact invite QR code";
            invite_code_btn.clicked.connect (show_invite_code_dialog);
            invite_code_box.append (invite_code_btn);

            var invite_code_label = new Gtk.Label ("Share your contact");
            invite_code_label.add_css_class ("dim-label");
            invite_code_label.valign = Gtk.Align.CENTER;
            invite_code_label.wrap = true;
            invite_code_label.xalign = 0;
            invite_code_label.hexpand = true;
            invite_code_box.append (invite_code_label);

            content.append (invite_code_box);

            var relays_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            relays_box.margin_top = 4;

            var relays_btn = new Gtk.Button.with_label ("Relays...");
            relays_btn.tooltip_text = "Manage chatmail relays for this profile";
            relays_btn.clicked.connect (show_relays_dialog);
            relays_box.append (relays_btn);

            var relays_label = new Gtk.Label ("Manage transports");
            relays_label.add_css_class ("dim-label");
            relays_label.valign = Gtk.Align.CENTER;
            relays_label.wrap = true;
            relays_label.xalign = 0;
            relays_label.hexpand = true;
            relays_box.append (relays_label);

            content.append (relays_box);

            var second_device_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            second_device_box.margin_top = 4;

            var second_device_btn = new Gtk.Button.with_label ("Add Second Device");
            second_device_btn.tooltip_text = "Show a setup QR code for another device";
            second_device_btn.clicked.connect (show_second_device_dialog);
            second_device_box.append (second_device_btn);

            var second_device_label = new Gtk.Label ("Transfer to another device");
            second_device_label.add_css_class ("dim-label");
            second_device_label.valign = Gtk.Align.CENTER;
            second_device_label.wrap = true;
            second_device_label.xalign = 0;
            second_device_label.hexpand = true;
            second_device_box.append (second_device_label);

            content.append (second_device_box);

            var delete_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            delete_box.margin_top = 4;

            var delete_btn = new Gtk.Button.with_label ("Delete Profile");
            delete_btn.add_css_class ("destructive-action");
            delete_btn.tooltip_text = "Delete local profile data";
            delete_btn.clicked.connect (confirm_delete_account);
            delete_box.append (delete_btn);

            var delete_label = new Gtk.Label ("Delete local profile data");
            delete_label.add_css_class ("dim-label");
            delete_label.valign = Gtk.Align.CENTER;
            delete_label.wrap = true;
            delete_label.xalign = 0;
            delete_label.hexpand = true;
            delete_box.append (delete_label);

            content.append (delete_box);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = content;
            box.append (scroll);

            this.child = box;

            load_profile.begin ();
            load_connectivity_summary.begin ();
        }

        private Gtk.Widget build_connectivity_storage_section () {
            var section = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);

            var title = new Gtk.Label ("Storage & Connectivity");
            title.add_css_class ("heading");
            title.halign = Gtk.Align.START;
            section.append (title);

            var conn_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var conn_icon = new Gtk.Image.from_icon_name ("network-transmit-receive-symbolic");
            conn_icon.valign = Gtk.Align.CENTER;
            conn_row.append (conn_icon);

            connectivity_status_label = new Gtk.Label ("Checking connection…");
            connectivity_status_label.halign = Gtk.Align.START;
            connectivity_status_label.xalign = 0;
            connectivity_status_label.wrap = true;
            connectivity_status_label.hexpand = true;
            connectivity_status_label.add_css_class ("dim-label");
            conn_row.append (connectivity_status_label);
            section.append (conn_row);

            storage_progress = new Gtk.ProgressBar ();
            storage_progress.add_css_class ("storage-quota-bar");
            storage_progress.fraction = 0.0;
            section.append (storage_progress);

            storage_summary_label = new Gtk.Label ("Loading server quota…");
            storage_summary_label.halign = Gtk.Align.START;
            storage_summary_label.xalign = 0;
            storage_summary_label.wrap = true;
            storage_summary_label.add_css_class ("dim-label");
            section.append (storage_summary_label);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.END;

            var refresh_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            refresh_btn.tooltip_text = "Refresh storage and connectivity";
            refresh_btn.add_css_class ("flat");
            refresh_btn.clicked.connect (() => {
                load_connectivity_summary.begin ();
            });
            actions.append (refresh_btn);

            var details_btn = new Gtk.Button.with_label ("Details…");
            details_btn.tooltip_text = "Show storage by conversation";
            details_btn.clicked.connect (() => {
                var dialog = new StorageDetailsDialog (rpc, account_id);
                dialog.present (this);
            });
            actions.append (details_btn);
            section.append (actions);

            return section;
        }

        private async void load_profile () {
            try {
                string? name = yield rpc.get_config ("displayname", account_id);
                string? status = yield rpc.get_config ("selfstatus", account_id);
                string? email = yield rpc.get_config ("addr", account_id);
                string? avatar = yield rpc.get_config ("selfavatar", account_id);

                if (name != null) {
                    name_entry.text = name;
                    avatar_widget.text = name;
                }
                if (status != null) status_entry.text = status;
                if (email != null) email_label.label = email;
                if (avatar != null && avatar.length > 0 &&
                    FileUtils.test (avatar, FileTest.EXISTS)) {
                    avatar_path = avatar;
                }
                avatar_widget.custom_image = load_avatar (avatar);
            } catch (Error e) {
                /* ignore */
            }
        }

        private async void load_connectivity_summary () {
            try {
                int connectivity = yield rpc.get_connectivity (account_id);
                connectivity_status_label.label =
                    connection_label_for_state (connectivity);

                string html = yield rpc.get_connectivity_html (account_id);
                var quota = StorageQuota.from_connectivity_html (html);
                set_storage_quota_summary (quota);
            } catch (Error e) {
                connectivity_status_label.label = "Connection details unavailable";
                storage_summary_label.label = e.message;
                storage_progress.fraction = 0.0;
            }
        }

        private void set_storage_quota_summary (StorageQuota quota) {
            storage_progress.remove_css_class ("storage-quota-warning");
            storage_progress.remove_css_class ("storage-quota-error");

            if (!quota.available || quota.limit_bytes <= 0) {
                storage_progress.fraction = 0.0;
                storage_summary_label.label =
                    "Server quota has not been reported yet.";
                return;
            }

            double fraction = (double) quota.used_bytes / (double) quota.limit_bytes;
            if (fraction < 0.0) fraction = 0.0;
            if (fraction > 1.0) fraction = 1.0;
            storage_progress.fraction = fraction;

            if (fraction >= 0.95) {
                storage_progress.add_css_class ("storage-quota-error");
            } else if (fraction >= 0.75) {
                storage_progress.add_css_class ("storage-quota-warning");
            }

            int64 left = quota.limit_bytes - quota.used_bytes;
            if (left < 0) left = 0;
            storage_summary_label.label = "%s used · %s left of %s".printf (
                format_mb (quota.used_bytes),
                format_mb (left),
                format_mb (quota.limit_bytes));
        }

        private static string connection_label_for_state (int state) {
            if (state >= 4000) return "Connected; all background work is done";
            if (state >= 3000) return "Connected; sending or syncing messages";
            if (state >= 2000) return "Connecting to the server";
            if (state >= 1000) return "Not connected";
            return "Connection state unknown";
        }

        private async void do_save () {
            try {
                yield rpc.batch_set_config ("displayname", name_entry.text.strip (), account_id);
                yield rpc.batch_set_config ("selfstatus", status_entry.text.strip (), account_id);
                if (avatar_changed && avatar_path != null) {
                    yield rpc.batch_set_config ("selfavatar", avatar_path, account_id);
                }
                profile_updated ();
                this.close ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private void show_invite_code_dialog () {
            var dialog = new InviteCodeDialog (rpc, account_id);
            dialog.present (this);
        }

        private void show_second_device_dialog () {
            var dialog = new SecondDeviceDialog (rpc, account_id);
            dialog.present (this);
        }

        private void show_relays_dialog () {
            var dialog = new RelaysDialog (rpc, account_id);
            dialog.present (this);
        }

        private void confirm_delete_account () {
            string label = email_label.label.strip ();
            if (label.length == 0) {
                label = name_entry.text.strip ();
            }
            if (label.length == 0) {
                label = "this account";
            }

            confirm_action (this, "Delete Profile",
                "Delete \"%s\"? This will remove all local data for this profile.".printf (label),
                "delete", "Delete Profile", () => { do_delete_account.begin (); });
        }

        private async void do_delete_account () {
            try {
                yield rpc.remove_account (account_id);
                if (rpc.account_id == account_id) {
                    rpc.account_id = 0;
                }
                account_deleted (account_id);
                this.close ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private async void pick_avatar () {
            string? path = yield pick_image_file (
                (Gtk.Window) this.get_root (), "Select Avatar");
            if (path != null) {
                avatar_path = path;
                avatar_changed = true;
                avatar_widget.custom_image = load_avatar (path);
            }
        }
    }

    private class StorageQuota : Object {
        public bool available { get; set; default = false; }
        public int64 used_bytes { get; set; default = 0; }
        public int64 limit_bytes { get; set; default = 0; }

        public static StorageQuota from_connectivity_html (string html) {
            var quota = new StorageQuota ();
            string text = strip_html (html);

            try {
                var rx = new Regex (
                    "([0-9]+(?:[\\.,][0-9]+)?)\\s*([KMGT]?i?B)\\s+of\\s+" +
                    "([0-9]+(?:[\\.,][0-9]+)?)\\s*([KMGT]?i?B)\\s+used",
                    RegexCompileFlags.CASELESS);
                MatchInfo match;
                if (rx.match (text, 0, out match)) {
                    double used = parse_number (match.fetch (1));
                    string used_unit = match.fetch (2);
                    double limit = parse_number (match.fetch (3));
                    string limit_unit = match.fetch (4);
                    quota.used_bytes = unit_to_bytes (used, used_unit);
                    quota.limit_bytes = unit_to_bytes (limit, limit_unit);
                    quota.available = quota.limit_bytes > 0;
                }
            } catch (Error e) {
                /* keep unavailable */
            }

            return quota;
        }

        private static string strip_html (string html) {
            string text = html;
            try {
                var tags = new Regex ("<[^>]+>");
                text = tags.replace (text, -1, 0, " ");
            } catch (Error e) { /* fallback */ }

            text = text.replace ("&nbsp;", " ");
            text = text.replace ("&amp;", "&");
            text = text.replace ("&lt;", "<");
            text = text.replace ("&gt;", ">");
            text = text.replace ("&quot;", "\"");
            try {
                var spaces = new Regex ("\\s+");
                text = spaces.replace (text, -1, 0, " ");
            } catch (Error e) { /* fallback */ }
            return text.strip ();
        }

        private static double parse_number (string s) {
            return double.parse (s.replace (",", "."));
        }

        private static int64 unit_to_bytes (double value, string unit) {
            string u = unit.up ();
            double mult = 1.0;
            if (u == "KB" || u == "KIB") mult = 1024.0;
            else if (u == "MB" || u == "MIB") mult = 1024.0 * 1024.0;
            else if (u == "GB" || u == "GIB") mult = 1024.0 * 1024.0 * 1024.0;
            else if (u == "TB" || u == "TIB") mult = 1024.0 * 1024.0 * 1024.0 * 1024.0;
            return (int64) (value * mult);
        }
    }

    private class ChatStorageUsage : Object {
        public int chat_id;
        public string name;
        public int message_count = 0;
        public int local_file_count = 0;
        public int64 remote_bytes = 0;
        public int64 local_bytes = 0;
        private HashTable<string,string> local_paths =
            new HashTable<string,string> (str_hash, str_equal);

        public ChatStorageUsage (int chat_id, string name) {
            this.chat_id = chat_id;
            this.name = name;
        }

        public bool add_local_file (string path, int64 bytes) {
            if (local_paths.contains (path)) return false;
            local_paths.insert (path, "1");
            local_bytes += bytes;
            local_file_count++;
            return true;
        }

        public int64 total_bytes () {
            return local_bytes > remote_bytes ? local_bytes : remote_bytes;
        }
    }

    public class StorageDetailsDialog : Adw.Dialog {
        private RpcClient rpc;
        private int account_id;
        private Gtk.ProgressBar quota_progress;
        private Gtk.Label quota_label;
        private Gtk.Label local_total_label;
        private Gtk.Label scan_status_label;
        private Gtk.ListBox chat_usage_list;
        private Gtk.Button refresh_btn;
        private Gtk.Button clear_cache_btn;
        private string? blob_dir = null;
        private int64 known_attachment_bytes = 0;
        private int64 unique_local_file_bytes = 0;
        private HashTable<string,string> global_local_paths =
            new HashTable<string,string> (str_hash, str_equal);

        public StorageDetailsDialog (RpcClient rpc, int acct_id) {
            this.rpc = rpc;
            this.account_id = acct_id;
            this.title = "Storage Details";
            this.content_width = 560;
            this.content_height = 680;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var header = new Adw.HeaderBar ();
            refresh_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic");
            refresh_btn.tooltip_text = "Rescan storage usage";
            refresh_btn.clicked.connect (() => { load_details.begin (); });
            header.pack_end (refresh_btn);
            box.append (header);

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_start = 16;
            content.margin_end = 16;
            content.margin_top = 12;
            content.margin_bottom = 16;

            var quota_title = new Gtk.Label ("Server Quota");
            quota_title.add_css_class ("heading");
            quota_title.halign = Gtk.Align.START;
            content.append (quota_title);

            quota_progress = new Gtk.ProgressBar ();
            quota_progress.add_css_class ("storage-quota-bar");
            content.append (quota_progress);

            quota_label = new Gtk.Label ("Loading quota…");
            quota_label.halign = Gtk.Align.START;
            quota_label.xalign = 0;
            quota_label.wrap = true;
            quota_label.add_css_class ("dim-label");
            content.append (quota_label);

            var local_title = new Gtk.Label ("Local Copies");
            local_title.add_css_class ("heading");
            local_title.halign = Gtk.Align.START;
            content.append (local_title);

            local_total_label = new Gtk.Label ("Scanning local files…");
            local_total_label.halign = Gtk.Align.START;
            local_total_label.xalign = 0;
            local_total_label.wrap = true;
            local_total_label.add_css_class ("dim-label");
            content.append (local_total_label);

            clear_cache_btn = new Gtk.Button.with_label ("Clear Local Cache…");
            clear_cache_btn.halign = Gtk.Align.START;
            clear_cache_btn.tooltip_text = "Explain what can be safely cleared";
            clear_cache_btn.clicked.connect (show_clear_cache_info);
            content.append (clear_cache_btn);

            content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            var chats_title = new Gtk.Label ("Conversations by Storage Size");
            chats_title.add_css_class ("heading");
            chats_title.halign = Gtk.Align.START;
            content.append (chats_title);

            scan_status_label = new Gtk.Label ("Preparing scan…");
            scan_status_label.halign = Gtk.Align.START;
            scan_status_label.xalign = 0;
            scan_status_label.wrap = true;
            scan_status_label.add_css_class ("dim-label");
            content.append (scan_status_label);

            chat_usage_list = new Gtk.ListBox ();
            chat_usage_list.selection_mode = Gtk.SelectionMode.NONE;
            chat_usage_list.add_css_class ("boxed-list");
            content.append (chat_usage_list);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = content;
            box.append (scroll);

            this.child = box;
            install_escape_close (this);
            load_details.begin ();
        }

        private async void load_details () {
            refresh_btn.sensitive = false;
            clear_listbox (chat_usage_list);
            known_attachment_bytes = 0;
            unique_local_file_bytes = 0;
            global_local_paths.remove_all ();
            scan_status_label.label = "Scanning conversations…";
            local_total_label.label = "Scanning local files…";

            try {
                int64 account_bytes = 0;
                try {
                    account_bytes = yield rpc.get_account_file_size (account_id);
                } catch (Error e) { /* optional in older RPC servers */ }

                try {
                    blob_dir = yield rpc.get_blob_dir (account_id);
                } catch (Error e) {
                    blob_dir = null;
                }

                try {
                    string html = yield rpc.get_connectivity_html (account_id);
                    set_quota (StorageQuota.from_connectivity_html (html));
                } catch (Error e) {
                    quota_progress.fraction = 0.0;
                    quota_label.label = "Server quota unavailable: " + e.message;
                }

                var usages = yield scan_all_chats ();
                sort_usages (usages);
                populate_chat_usage_list (usages);

                if (account_bytes > 0) {
                    local_total_label.label =
                        "%s local account data · %s downloaded message files · %s known attachment payload".printf (
                            format_mb (account_bytes),
                            format_mb (unique_local_file_bytes),
                            format_mb (known_attachment_bytes));
                } else {
                    local_total_label.label =
                        "%s downloaded message files · %s known attachment payload".printf (
                            format_mb (unique_local_file_bytes),
                            format_mb (known_attachment_bytes));
                }

                scan_status_label.label = usages.length == 0
                    ? "No downloaded message files found in conversations."
                    : "%d conversations with local or attached files.".printf (usages.length);
            } catch (Error e) {
                scan_status_label.label = "Storage scan failed: " + e.message;
            }

            refresh_btn.sensitive = true;
        }

        private void set_quota (StorageQuota quota) {
            quota_progress.remove_css_class ("storage-quota-warning");
            quota_progress.remove_css_class ("storage-quota-error");

            if (!quota.available || quota.limit_bytes <= 0) {
                quota_progress.fraction = 0.0;
                quota_label.label = "Server quota has not been reported yet.";
                return;
            }

            double fraction = (double) quota.used_bytes / (double) quota.limit_bytes;
            if (fraction < 0.0) fraction = 0.0;
            if (fraction > 1.0) fraction = 1.0;
            quota_progress.fraction = fraction;

            if (fraction >= 0.95) quota_progress.add_css_class ("storage-quota-error");
            else if (fraction >= 0.75) quota_progress.add_css_class ("storage-quota-warning");

            int64 left = quota.limit_bytes - quota.used_bytes;
            if (left < 0) left = 0;
            quota_label.label = "%s used · %s left of %s".printf (
                format_mb (quota.used_bytes),
                format_mb (left),
                format_mb (quota.limit_bytes));
        }

        private async ChatStorageUsage[] scan_all_chats () throws Error {
            ChatStorageUsage[] usages = {};
            var entries = yield rpc.get_chatlist_entries_for (account_id);
            if (entries == null) return usages;

            Json.Object? items = null;
            try {
                items = yield rpc.get_chatlist_items_by_entries_for (account_id, entries);
            } catch (Error e) { /* names fall back to ids */ }

            for (uint i = 0; i < entries.get_length (); i++) {
                int chat_id = (int) entries.get_int_element (i);
                string name = get_chat_name (items, chat_id);
                scan_status_label.label = "Scanning %s…".printf (name);

                var usage = yield scan_chat (chat_id, name);
                if (usage.remote_bytes > 0 || usage.local_bytes > 0) {
                    usages += usage;
                }
            }
            return usages;
        }

        private string get_chat_name (Json.Object? items, int chat_id) {
            if (items != null) {
                string key = chat_id.to_string ();
                if (items.has_member (key)) {
                    var entry = RpcClient.parse_chat_item (
                        chat_id, items.get_object_member (key));
                    if (entry.name.length > 0) return entry.name;
                }
            }
            return "Chat #%d".printf (chat_id);
        }

        private async ChatStorageUsage scan_chat (int chat_id,
                                                   string name) throws Error {
            var usage = new ChatStorageUsage (chat_id, name);
            var ids = yield rpc.get_message_ids_for (account_id, chat_id);
            if (ids == null) return usage;
            usage.message_count = (int) ids.get_length ();

            int len = (int) ids.get_length ();
            for (int start = 0; start < len; start += 200) {
                int end = start + 200;
                if (end > len) end = len;
                int count = end - start;
                int[] batch = new int[count];
                for (int i = 0; i < count; i++) {
                    batch[i] = (int) ids.get_int_element ((uint) (start + i));
                }

                var messages = yield rpc.get_messages_for (account_id, batch);
                if (messages == null) continue;

                for (int i = 0; i < count; i++) {
                    string key = batch[i].to_string ();
                    if (!messages.has_member (key)) continue;

                    var node = messages.get_member (key);
                    if (node == null || node.get_node_type () != Json.NodeType.OBJECT)
                        continue;

                    var msg = RpcClient.parse_message (node.get_object ());
                    add_message_usage (usage, msg);
                }
            }
            return usage;
        }

        private void add_message_usage (ChatStorageUsage usage, Message msg) {
            if (msg.file_bytes > 0) {
                usage.remote_bytes += msg.file_bytes;
                known_attachment_bytes += msg.file_bytes;
            }

            string? local_path = resolve_local_path (msg.file_path);
            if (local_path == null) return;

            int64 bytes = file_size (local_path);
            if (bytes <= 0) return;

            usage.add_local_file (local_path, bytes);
            if (!global_local_paths.contains (local_path)) {
                global_local_paths.insert (local_path, "1");
                unique_local_file_bytes += bytes;
            }
        }

        private string? resolve_local_path (string? path) {
            if (path == null || path.length == 0) return null;
            if (path.has_prefix ("$BLOBDIR/")) {
                if (blob_dir == null || blob_dir.length == 0) return null;
                return Path.build_filename (blob_dir, path.substring (9));
            }
            if (Path.is_absolute (path)) return path;
            return null;
        }

        private static int64 file_size (string path) {
            if (!FileUtils.test (path, FileTest.IS_REGULAR)) return 0;
            try {
                var info = File.new_for_path (path).query_info (
                    "standard::size", FileQueryInfoFlags.NONE);
                return info.get_size ();
            } catch (Error e) {
                return 0;
            }
        }

        private void sort_usages (ChatStorageUsage[] usages) {
            for (int i = 0; i < usages.length; i++) {
                for (int j = i + 1; j < usages.length; j++) {
                    if (usages[j].total_bytes () > usages[i].total_bytes ()) {
                        var tmp = usages[i];
                        usages[i] = usages[j];
                        usages[j] = tmp;
                    }
                }
            }
        }

        private void populate_chat_usage_list (ChatStorageUsage[] usages) {
            clear_listbox (chat_usage_list);
            int64 max = 1;
            foreach (var usage in usages) {
                if (usage.total_bytes () > max) max = usage.total_bytes ();
            }

            foreach (var usage in usages) {
                chat_usage_list.append (build_chat_usage_row (usage, max));
            }
        }

        private Gtk.Widget build_chat_usage_row (ChatStorageUsage usage,
                                                  int64 max_bytes) {
            var row = new Gtk.ListBoxRow ();
            row.activatable = false;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 5);
            box.margin_start = 12;
            box.margin_end = 12;
            box.margin_top = 8;
            box.margin_bottom = 8;

            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var title = new Gtk.Label (usage.name);
            title.halign = Gtk.Align.START;
            title.xalign = 0;
            title.ellipsize = Pango.EllipsizeMode.END;
            title.hexpand = true;
            top.append (title);

            var amount = new Gtk.Label (format_mb (usage.total_bytes ()));
            amount.add_css_class ("numeric");
            amount.halign = Gtk.Align.END;
            top.append (amount);
            box.append (top);

            var subtitle = new Gtk.Label (
                "%s local · %s attached · %d files · %d messages".printf (
                    format_mb (usage.local_bytes),
                    format_mb (usage.remote_bytes),
                    usage.local_file_count,
                    usage.message_count));
            subtitle.halign = Gtk.Align.START;
            subtitle.xalign = 0;
            subtitle.wrap = true;
            subtitle.add_css_class ("dim-label");
            subtitle.add_css_class ("caption");
            box.append (subtitle);

            var bar = new Gtk.ProgressBar ();
            bar.add_css_class ("storage-chat-bar");
            bar.fraction = (double) usage.total_bytes () / (double) max_bytes;
            box.append (bar);

            row.child = box;
            return row;
        }

        private void show_clear_cache_info () {
            var dialog = new Adw.AlertDialog (
                "Clear Local Cache",
                "Parla can show downloaded local files, but Delta Chat does not expose a safe cache-only purge for message blobs through this RPC server. Deleting those files directly can break attachments and forwarded messages.\n\nUse the conversation list above to decide which chats or messages to remove. Delta Chat housekeeping then cleans unused local files."
            );
            dialog.add_response ("ok", "OK");
            dialog.present (this);
        }
    }

    private static string format_mb (int64 bytes) {
        double mb = (double) bytes / (1024.0 * 1024.0);
        return "%.1f MB".printf (mb);
    }

    public class InviteCodeDialog : Adw.Dialog {

        private RpcClient rpc;
        private int account_id;
        private Gtk.Label status_label;
        private Gtk.Picture qr_picture;
        private Gtk.TextView qr_text_view;
        private Gtk.ScrolledWindow qr_text_scroll;
        private Gtk.Button copy_btn;
        private string? invite_text = null;
        private bool closing = false;

        public InviteCodeDialog (RpcClient rpc, int acct_id) {
            this.rpc = rpc;
            this.account_id = acct_id;
            this.title = "Invite Code";
            this.content_width = 480;
            this.content_height = 560;
            this.can_close = true;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (new Adw.HeaderBar ());

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_start = 18;
            content.margin_end = 18;
            content.margin_top = 12;
            content.margin_bottom = 18;

            status_label = new Gtk.Label ("Preparing invite code…");
            status_label.wrap = true;
            status_label.xalign = 0;
            content.append (status_label);

            qr_picture = new Gtk.Picture ();
            qr_picture.content_fit = Gtk.ContentFit.CONTAIN;
            qr_picture.can_shrink = true;
            qr_picture.halign = Gtk.Align.CENTER;
            qr_picture.set_size_request (280, 280);
            qr_picture.visible = false;
            content.append (qr_picture);

            qr_text_view = new Gtk.TextView ();
            qr_text_view.editable = false;
            qr_text_view.cursor_visible = false;
            qr_text_view.monospace = true;
            qr_text_view.wrap_mode = Gtk.WrapMode.CHAR;

            qr_text_scroll = new Gtk.ScrolledWindow ();
            qr_text_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            qr_text_scroll.min_content_height = 96;
            qr_text_scroll.child = qr_text_view;
            qr_text_scroll.visible = false;
            content.append (qr_text_scroll);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.END;
            actions.margin_top = 6;

            copy_btn = new Gtk.Button.with_label ("Copy Link");
            copy_btn.sensitive = false;
            copy_btn.clicked.connect (copy_invite_text);
            actions.append (copy_btn);

            var close_btn = new Gtk.Button.with_label ("Close");
            close_btn.clicked.connect (() => { this.close (); });
            actions.append (close_btn);
            content.append (actions);

            box.append (content);
            this.child = box;

            install_escape_close (this);
            this.closed.connect (() => { closing = true; });
            load_invite_code.begin ();
        }

        private async void load_invite_code () {
            try {
                string text = yield rpc.get_chat_securejoin_qr_code (account_id);
                string svg = yield rpc.create_qr_svg (text);
                if (!closing) show_qr (text, svg);
            } catch (Error e) {
                if (!closing) show_invite_error (e.message);
            }
        }

        private void show_qr (string text, string svg) {
            invite_text = text;
            status_label.label = "Share this QR code with another user, or copy the invite link below.";
            qr_text_view.buffer.text = text;
            qr_text_scroll.visible = true;
            copy_btn.sensitive = true;

            try {
                var bytes = new Bytes (svg.data);
                qr_picture.paintable = Gdk.Texture.from_bytes (bytes);
                qr_picture.visible = true;
            } catch (Error e) {
                status_label.label = "Invite link is ready, but the QR image could not be rendered: " + e.message;
            }
        }

        private void show_invite_error (string message) {
            status_label.label = "Invite code creation failed: " + message;
            copy_btn.sensitive = false;
        }

        private void copy_invite_text () {
            if (invite_text == null || invite_text.length == 0) return;
            this.get_display ().get_clipboard ().set_text (invite_text);
        }
    }

    public class SecondDeviceDialog : Adw.Dialog {

        private RpcClient rpc;
        private int account_id;
        private Gtk.Label status_label;
        private Gtk.Picture qr_picture;
        private Gtk.TextView qr_text_view;
        private Gtk.ScrolledWindow qr_text_scroll;
        private Gtk.Button copy_btn;
        private string? qr_text = null;
        private bool closing = false;
        private bool provider_running = false;

        public SecondDeviceDialog (RpcClient rpc, int acct_id) {
            this.rpc = rpc;
            this.account_id = acct_id;
            this.title = "Add Second Device";
            this.content_width = 480;
            this.content_height = 560;
            this.can_close = true;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.append (new Adw.HeaderBar ());

            var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_start = 18;
            content.margin_end = 18;
            content.margin_top = 12;
            content.margin_bottom = 18;

            status_label = new Gtk.Label ("Preparing account…");
            status_label.wrap = true;
            status_label.xalign = 0;
            content.append (status_label);

            qr_picture = new Gtk.Picture ();
            qr_picture.content_fit = Gtk.ContentFit.CONTAIN;
            qr_picture.can_shrink = true;
            qr_picture.halign = Gtk.Align.CENTER;
            qr_picture.set_size_request (280, 280);
            qr_picture.visible = false;
            content.append (qr_picture);

            qr_text_view = new Gtk.TextView ();
            qr_text_view.editable = false;
            qr_text_view.cursor_visible = false;
            qr_text_view.monospace = true;
            qr_text_view.wrap_mode = Gtk.WrapMode.CHAR;

            qr_text_scroll = new Gtk.ScrolledWindow ();
            qr_text_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            qr_text_scroll.min_content_height = 96;
            qr_text_scroll.child = qr_text_view;
            qr_text_scroll.visible = false;
            content.append (qr_text_scroll);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.END;
            actions.margin_top = 6;

            copy_btn = new Gtk.Button.with_label ("Copy Text");
            copy_btn.sensitive = false;
            copy_btn.clicked.connect (copy_qr_text);
            actions.append (copy_btn);

            var close_btn = new Gtk.Button.with_label ("Close");
            close_btn.clicked.connect (() => { this.close (); });
            actions.append (close_btn);
            content.append (actions);

            box.append (content);
            this.child = box;

            install_escape_close (this);
            this.closed.connect (on_closed);
            start_transfer.begin ();
        }

        private async void start_transfer () {
            provider_running = true;
            rpc.provide_backup.begin (account_id, (obj, res) => {
                provider_running = false;
                try {
                    rpc.provide_backup.end (res);
                    if (!closing) this.close ();
                } catch (Error e) {
                    if (!closing) show_transfer_error (e.message);
                }
            });

            try {
                string text = yield rpc.get_backup_qr (account_id);
                string svg = yield rpc.create_qr_svg (text);
                if (!closing) show_qr (text, svg);
            } catch (Error e) {
                if (!closing) {
                    show_transfer_error (e.message);
                    stop_provider ();
                }
            }
        }

        private void show_qr (string text, string svg) {
            qr_text = text;
            status_label.label = "Scan this QR code with the second device, or copy the text below.";
            qr_text_view.buffer.text = text;
            qr_text_scroll.visible = true;
            copy_btn.sensitive = true;

            try {
                var bytes = new Bytes (svg.data);
                qr_picture.paintable = Gdk.Texture.from_bytes (bytes);
                qr_picture.visible = true;
            } catch (Error e) {
                status_label.label = "QR text is ready, but the image could not be rendered: " + e.message;
            }
        }

        private void show_transfer_error (string message) {
            status_label.label = "Second-device setup failed: " + message;
            copy_btn.sensitive = false;
        }

        private void copy_qr_text () {
            if (qr_text == null || qr_text.length == 0) return;
            this.get_display ().get_clipboard ().set_text (qr_text);
        }

        private void on_closed () {
            closing = true;
            stop_provider ();
        }

        private void stop_provider () {
            if (provider_running) {
                rpc.stop_ongoing_process.begin (account_id, (obj, res) => {
                    try { rpc.stop_ongoing_process.end (res); }
                    catch (Error e) { /* ignore */ }
                });
            }
        }
    }
}
