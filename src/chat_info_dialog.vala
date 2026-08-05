namespace Dc {

    public class ChatInfoDialog : Adw.Dialog {

        private unowned Window app_window;
        private RpcClient rpc;
        private int chat_id;
        private bool is_group = false;
        private Gtk.ListBox? members_list = null;
        private Gtk.Box content;
        private string chat_name = "";
        private int[] member_contact_ids = {};
        private Contact? dm_contact = null;

        public signal void chat_deleted (int chat_id);
        public signal void chat_changed ();
        public signal void contact_blocked (int chat_id);

        private Gtk.ListBox boxed_list () {
            var list = new Gtk.ListBox ();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.add_css_class ("boxed-list");
            return list;
        }

        private void style_flat_button (Gtk.Button button,
                                        bool error = false) {
            button.valign = Gtk.Align.CENTER;
            button.add_css_class ("flat");
            if (error) button.add_css_class ("error");
        }

        private Gtk.Button flat_button (string label, owned VoidFunc action,
                                        bool error = false) {
            var button = new Gtk.Button.with_label (label);
            style_flat_button (button, error);
            button.clicked.connect (() => { action (); });
            return button;
        }

        private Gtk.Button flat_icon_button (string icon_name,
                                             string tooltip,
                                             owned VoidFunc action,
                                             bool error = false) {
            var button = new Gtk.Button.from_icon_name (icon_name);
            style_flat_button (button, error);
            button.tooltip_text = tooltip;
            button.clicked.connect (() => { action (); });
            return button;
        }

        private Adw.ActionRow action_row (string title, string subtitle,
                                          string icon_name,
                                          owned VoidFunc action) {
            var row = new Adw.ActionRow ();
            row.title = title;
            row.subtitle = subtitle;
            row.add_prefix (new Gtk.Image.from_icon_name (icon_name));
            row.activatable = true;
            row.activated.connect (() => { action (); });
            return row;
        }

        public ChatInfoDialog (Window window, RpcClient rpc, int chat_id) {
            this.app_window = window;
            this.rpc = rpc;
            this.chat_id = chat_id;
            this.title = "Chat Info";
            this.content_width = 360;
            this.content_height = 500;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = true;
            box.append (header);

            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
            content.margin_start = 16;
            content.margin_end = 16;
            content.margin_top = 12;
            content.margin_bottom = 16;

            var spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.halign = Gtk.Align.CENTER;
            spinner.margin_top = 40;
            content.append (spinner);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = content;
            box.append (scroll);

            this.child = box;

            load_info.begin (spinner);
        }

        private async void load_info (Gtk.Spinner spinner) {
            try {
                var chat = yield rpc.get_full_chat_by_id_for (
                    rpc.account_id, chat_id);
                if (chat == null) return;

                spinner.visible = false;

                string name = json_str (chat, "name") ?? "Chat";
                string chat_type = json_str (chat, "chatType") ?? "";
                string? profile_image = json_str (chat, "profileImage");
                bool encrypted = json_bool (chat, "isEncrypted");
                bool is_dm_chat = chat_type == "Single"
                    && !json_bool (chat, "isSelfTalk")
                    && !json_bool (chat, "isDeviceChat");

                is_group = chat_type == "Group" || chat_type == "Broadcast";
                chat_name = name;
                dm_contact = null;

                int dm_contact_id = 0;
                if (is_dm_chat && chat.has_member ("contactIds")) {
                    var ids = chat.get_array_member ("contactIds");
                    if (ids.get_length () > 0)
                        dm_contact_id = (int) ids.get_int_element (0);
                }

                var avatar = new Adw.Avatar (80, name, true);
                avatar.custom_image = load_avatar (profile_image);
                avatar.halign = Gtk.Align.CENTER;
                content.append (avatar);

                if (is_group) {
                    var change_avatar_btn = flat_button ("Change Avatar",
                        () => { pick_avatar.begin (); });
                    change_avatar_btn.halign = Gtk.Align.CENTER;
                    content.append (change_avatar_btn);
                }

                var name_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                name_box.halign = Gtk.Align.CENTER;

                var name_lbl = new Gtk.Label (name);
                name_lbl.add_css_class ("title-1");
                name_lbl.ellipsize = Pango.EllipsizeMode.END;
                name_lbl.max_width_chars = 24;
                name_box.append (name_lbl);

                if (is_dm_chat && dm_contact_id > 1) {
                    name_box.append (flat_icon_button (
                        "document-edit-symbolic", "Edit contact name",
                        () => {
                            show_edit_contact_name_dialog (dm_contact_id, name_lbl);
                        }));
                } else if (is_group) {
                    name_box.append (flat_icon_button (
                        "document-edit-symbolic", "Edit group name",
                        () => {
                            show_edit_group_name_dialog (name_lbl);
                        }));
                }

                content.append (name_box);

                string type_str = chat_type;
                if (encrypted) type_str += " (encrypted)";
                var type_lbl = new Gtk.Label (type_str);
                type_lbl.add_css_class ("dim-label");
                type_lbl.halign = Gtk.Align.CENTER;
                content.append (type_lbl);

                if (is_group) {
                    var invite_list = boxed_list ();
                    invite_list.append (action_row ("Invite Link",
                        "Share a link or QR code for others to join",
                        "mail-forward-symbolic", () => {
                        var dialog = new InviteCodeDialog (rpc, rpc.account_id, chat_id);
                        dialog.present (this);
                    }));
                    content.append (invite_list);
                }

                int ephemeral_timer = (int) json_int (chat, "ephemeralTimer");

                var ephem_row = new Adw.ActionRow ();
                ephem_row.title = "Disappearing messages";

                int[] timer_values = { 0, 60, 300, 1800, 3600, 21600, 86400, 604800, 2419200 };
                string[] timer_labels = {
                    "Off", "1 minute", "5 minutes", "30 minutes",
                    "1 hour", "6 hours", "1 day", "1 week", "4 weeks"
                };
                int active_idx = 0;
                for (int i = 0; i < timer_values.length; i++) {
                    if (timer_values[i] == ephemeral_timer) {
                        active_idx = i;
                    }
                }
                var combo = new Gtk.DropDown.from_strings (timer_labels);
                combo.selected = active_idx;
                combo.valign = Gtk.Align.CENTER;
                combo.notify["selected"].connect (() => {
                    uint idx = combo.selected;
                    if (idx < timer_values.length) {
                        rpc.set_chat_ephemeral_timer.begin (
                            chat_id, timer_values[(int) idx]);
                    }
                });
                ephem_row.add_suffix (combo);
                ephem_row.activatable_widget = combo;

                /* Mute selector. Core only reports the boolean isMuted, not
                   the remaining time, so a timed mute shows as "Forever"
                   here; picking any entry always applies that duration. */
                bool is_muted = json_bool (chat, "isMuted");
                var mute_row = new Adw.ActionRow ();
                mute_row.title = "Mute notifications";
                string[] mute_labels = new string[MUTE_DURATION_LABELS.length + 1];
                mute_labels[0] = "Off";
                for (int i = 0; i < MUTE_DURATION_LABELS.length; i++) {
                    mute_labels[i + 1] = MUTE_DURATION_LABELS[i];
                }
                var mute_combo = new Gtk.DropDown.from_strings (mute_labels);
                mute_combo.selected = is_muted ? mute_labels.length - 1 : 0;
                mute_combo.valign = Gtk.Align.CENTER;
                mute_combo.notify["selected"].connect (() => {
                    uint idx = mute_combo.selected;
                    if (idx < mute_labels.length) {
                        int secs = idx == 0
                            ? 0 : MUTE_DURATION_SECONDS[(int) idx - 1];
                        set_mute.begin (secs);
                    }
                });
                mute_row.add_suffix (mute_combo);
                mute_row.activatable_widget = mute_combo;

                var ephem_list = boxed_list ();
                ephem_list.append (action_row (
                    "View Media",
                    "Browse apps and media shared in this chat",
                    "view-grid-symbolic",
                    () => {
                        var dialog = new GalleryDialog (
                            app_window, rpc, chat_id, chat_name);
                        dialog.presenter_dialog = this;
                        dialog.present (this);
                    }));
                ephem_list.append (mute_row);
                ephem_list.append (ephem_row);
                content.append (ephem_list);

                content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

                if (chat.has_member ("contactIds")) {
                    var ids = chat.get_array_member ("contactIds");

                    var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

                    var members_lbl = new Gtk.Label (
                        is_group ? "Members (%u)".printf (ids.get_length ()) : "Contact");
                    members_lbl.add_css_class ("heading");
                    members_lbl.halign = Gtk.Align.START;
                    members_lbl.hexpand = true;
                    header_box.append (members_lbl);

                    if (is_group) {
                        header_box.append (flat_icon_button (
                            "list-add-symbolic", "Add member",
                            () => { add_member_dialog.begin (); }));
                    }

                    content.append (header_box);

                    members_list = boxed_list ();

                    for (uint i = 0; i < ids.get_length (); i++) {
                        int cid = (int) ids.get_int_element (i);
                        member_contact_ids += cid;
                        var contact_obj = yield rpc.get_contact_for (
                            rpc.account_id, cid);
                        var contact = contact_obj != null
                            ? RpcParsers.parse_contact (cid, contact_obj)
                            : null;
                        if (contact == null) continue;
                        if (is_dm_chat && contact.id > 1 && dm_contact == null)
                            dm_contact = contact;

                        var row = build_contact_row (contact);
                        members_list.append (row);
                    }

                    content.append (members_list);
                }

                content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

                var actions_list = boxed_list ();

                actions_list.append (action_row ("Clear Chat",
                    "Remove messages from this device",
                    "edit-clear-symbolic",
                    () => { confirm_clear_history (false); }));

                actions_list.append (action_row ("Clear Sent Messages for Everyone",
                    "Delete messages you sent for all participants",
                    "edit-delete-symbolic",
                    () => { confirm_clear_history (true); }));

                if (is_group) {
                    actions_list.append (action_row ("Leave Group",
                        "Stop receiving messages", "system-log-out-symbolic",
                        () => { confirm_leave_group (); }));
                    actions_list.append (action_row ("Disband Group",
                        "Remove all members and delete messages",
                        "edit-delete-symbolic",
                        () => { confirm_disband_group (); }));
                }

                if (dm_contact != null) {
                    actions_list.append (build_contact_block_row (dm_contact));
                }

                actions_list.append (action_row ("Delete for Me",
                    "Remove from your chat list", "user-trash-symbolic",
                    () => { confirm_delete_chat (); }));

                content.append (actions_list);

            } catch (Error e) {
                spinner.visible = false;
                var err = new Gtk.Label ("Failed to load: " + e.message);
                err.add_css_class ("dim-label");
                err.wrap = true;
                content.append (err);
            }
        }

        private async void set_mute (int seconds) {
            try {
                yield rpc.set_chat_mute_duration (chat_id, seconds);
                chat_changed ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private Adw.ActionRow build_contact_row (Contact contact) {
            var row = contact_row (contact, false, false);

            if (contact.address.length > 0) {
                string addr = contact.address;
                var copy_btn = flat_icon_button (
                    "edit-copy-symbolic", "Copy email address", () => {
                    var clipboard = this.get_clipboard ();
                    clipboard.set_text (addr);
                });
                row.add_suffix (copy_btn);
            }

            if (is_group && contact.id != 1) {
                int cid = contact.id;
                row.add_suffix (flat_icon_button (
                    "user-trash-symbolic", "Remove from group",
                    () => { remove_member.begin (cid, row); }, true));
            }

            return row;
        }

        private Adw.ActionRow build_contact_block_row (Contact contact) {
            var row = new Adw.ActionRow ();
            row.add_prefix (new Gtk.Image.from_icon_name ("action-unavailable-symbolic"));
            row.activatable = true;
            update_contact_block_row (row, contact);
            row.activated.connect (() => {
                if (contact.is_blocked) {
                    set_contact_blocked.begin (contact, row, false);
                } else {
                    confirm_block_contact (contact, row);
                }
            });
            return row;
        }

        private void update_contact_block_row (Adw.ActionRow row,
                                                Contact contact) {
            string label = contact_label (contact);
            if (contact.is_blocked) {
                row.title = "Unblock Contact";
                row.subtitle = "Allow messages from %s".printf (label);
            } else {
                row.title = "Block Contact";
                row.subtitle = "Stop receiving messages from %s".printf (label);
            }
        }

        private static string contact_label (Contact contact) {
            if (contact.display_name.length > 0) return contact.display_name;
            if (contact.address.length > 0) return contact.address;
            return "this contact";
        }

        private void show_edit_contact_name_dialog (int contact_id,
                                                    Gtk.Label name_lbl) {
            var dialog = new Adw.AlertDialog (
                "Edit Contact Name",
                "Leave empty to use the contact's own name."
            );

            var entry = new Gtk.Entry ();
            entry.text = name_lbl.label;
            entry.placeholder_text = "Contact name";
            entry.activates_default = true;
            entry.hexpand = true;

            dialog.extra_child = entry;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "save";
            dialog.close_response = "cancel";

            entry.activate.connect (() => {
                dialog.response ("save");
            });

            dialog.response.connect ((resp) => {
                if (resp == "save") {
                    save_contact_name.begin (
                        contact_id, entry.text.strip (), name_lbl);
                }
            });

            dialog.present (this);
            entry.grab_focus ();
        }

        private async void save_contact_name (int contact_id, string new_name,
                                              Gtk.Label name_lbl) {
            try {
                yield rpc.change_contact_name (contact_id, new_name);

                var contact_obj = yield rpc.get_contact_for (
                    rpc.account_id, contact_id);
                var contact = contact_obj != null
                    ? RpcParsers.parse_contact (contact_id, contact_obj)
                    : null;
                if (contact != null) {
                    dm_contact = contact;
                    chat_name = contact_label (contact);
                    name_lbl.label = chat_name;
                    if (members_list != null && !is_group) {
                        clear_listbox (members_list);
                        members_list.append (build_contact_row (contact));
                    }
                } else if (new_name.length > 0) {
                    chat_name = new_name;
                    name_lbl.label = new_name;
                }

                chat_changed ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private void show_edit_group_name_dialog (Gtk.Label name_lbl) {
            var dialog = new Adw.AlertDialog ("Edit Group Name", null);

            var entry = new Gtk.Entry ();
            entry.text = name_lbl.label;
            entry.placeholder_text = "Group name";
            entry.activates_default = true;
            entry.hexpand = true;

            dialog.extra_child = entry;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            dialog.default_response = "save";
            dialog.close_response = "cancel";

            entry.activate.connect (() => { dialog.response ("save"); });

            dialog.response.connect ((resp) => {
                if (resp != "save") return;
                string new_name = entry.text.strip ();
                /* Groups must keep a name, so ignore an empty entry. */
                if (new_name.length > 0)
                    save_group_name.begin (new_name, name_lbl);
            });

            dialog.present (this);
            entry.grab_focus ();
        }

        private async void save_group_name (string new_name, Gtk.Label name_lbl) {
            try {
                yield rpc.set_chat_name (chat_id, new_name);
                chat_name = new_name;
                name_lbl.label = new_name;
                chat_changed ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private async void remove_member (int contact_id, Adw.ActionRow row) {
            try {
                yield rpc.remove_contact_from_chat (chat_id, contact_id);
                members_list.remove (row);
            } catch (Error e) {
                row.subtitle = "Remove failed: " + e.message;
            }
        }

        private async void add_member_dialog () {
            var picker = new ContactPickerDialog (rpc);
            picker.contact_picked.connect ((_, email) => {
                do_add_member.begin (email);
            });
            picker.present (this);
        }

        private async void do_add_member (string email) {
            try {
                int contact_id = yield rpc.get_or_create_contact (email);
                yield rpc.add_contact_to_chat (chat_id, contact_id);

                var contact_obj = yield rpc.get_contact_for (
                    rpc.account_id, contact_id);
                var contact = contact_obj != null
                    ? RpcParsers.parse_contact (contact_id, contact_obj)
                    : null;
                if (contact != null && members_list != null) {
                    var row = build_contact_row (contact);
                    members_list.append (row);
                }
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private void confirm_block_contact (Contact contact, Adw.ActionRow row) {
            string label = contact_label (contact);
            confirm_action (this, "Block Contact",
                "Block \"%s\"? You will no longer receive messages from this contact.".printf (label),
                "block", "Block", () => {
                    set_contact_blocked.begin (contact, row, true);
                });
        }

        private async void set_contact_blocked (Contact contact,
                                                Adw.ActionRow row,
                                                bool blocked) {
            try {
                if (blocked) {
                    yield rpc.block_contact (contact.id);
                } else {
                    yield rpc.unblock_contact (contact.id);
                }
                contact.is_blocked = blocked;
                update_contact_block_row (row, contact);
                if (blocked) contact_blocked (chat_id);
                else chat_changed ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private void confirm_clear_history (bool for_all) {
            string title = for_all ? "Clear Sent Messages for Everyone" : "Clear Chat";
            string body = for_all
                ? "Delete messages you sent for all participants? Messages from other people can only be cleared from your device."
                : "Remove all messages from this device? The chat will stay in your conversation list.";
            string action_label = for_all ? "Clear Sent Messages" : "Clear Chat";
            confirm_action (this, title, body, "clear", action_label, () => {
                do_clear_history.begin (for_all);
            });
        }

        private async void do_clear_history (bool for_all) {
            try {
                yield delete_all_messages (for_all);
                chat_changed ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private async void delete_all_messages (bool for_all) throws Error {
            int[] ids = yield chat_message_ids_for_clear (
                rpc, rpc.account_id, chat_id, for_all);
            if (ids.length == 0) return;
            if (for_all) yield rpc.delete_messages_for_all (ids);
            else yield rpc.delete_messages (ids);
        }

        private void confirm_leave_group () {
            confirm_action (this, "Leave Group",
                "Leave \"%s\"? You will stop receiving messages.".printf (chat_name),
                "leave", "Leave", () => { do_leave_group.begin (); });
        }

        private async void do_leave_group () {
            try {
                yield rpc.leave_group (chat_id);
                chat_changed ();
                this.close ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private void confirm_disband_group () {
            confirm_action (this, "Disband Group",
                "Remove all members from \"%s\" and delete your sent messages for everyone? Other messages will only be removed locally.".printf (chat_name),
                "disband", "Disband", () => { do_disband_group.begin (); });
        }

        private async void do_disband_group () {
            try {
                foreach (int cid in member_contact_ids) {
                    if (cid != 1) {
                        yield rpc.remove_contact_from_chat (chat_id, cid);
                    }
                }

                yield delete_all_messages (true);
                yield rpc.leave_group (chat_id);
                yield rpc.delete_chat (chat_id);

                chat_deleted (chat_id);
                this.close ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private void confirm_delete_chat () {
            confirm_action (this, "Delete for Me",
                "Remove \"%s\" from your chat list? You may still receive messages if you are a member.".printf (chat_name),
                "delete", "Delete", () => { do_delete_chat_from_dialog.begin (); });
        }

        private async void do_delete_chat_from_dialog () {
            try {
                yield rpc.delete_chat (chat_id);
                chat_deleted (chat_id);
                this.close ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private async void pick_avatar () {
            string? path = yield pick_image_file (
                (Gtk.Window) this.get_root (), "Select Avatar Image");
            if (path == null) return;
            try {
                yield rpc.set_chat_profile_image (chat_id, path);
            } catch (Error e) { /* ignore */ }
        }
    }
}
