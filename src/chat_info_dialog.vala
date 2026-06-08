namespace Dc {

    public class ChatInfoDialog : Adw.Dialog {

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

        public ChatInfoDialog (RpcClient rpc, int chat_id) {
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
                var chat = yield rpc.get_full_chat_by_id (chat_id);
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

                /* Avatar */
                var avatar = new Adw.Avatar (80, name, true);
                avatar.custom_image = load_avatar (profile_image);
                avatar.halign = Gtk.Align.CENTER;
                content.append (avatar);

                /* Change avatar button for groups */
                if (is_group) {
                    var change_avatar_btn = new Gtk.Button.with_label ("Change Avatar");
                    change_avatar_btn.halign = Gtk.Align.CENTER;
                    change_avatar_btn.add_css_class ("flat");
                    change_avatar_btn.clicked.connect (() => {
                        pick_avatar.begin ();
                    });
                    content.append (change_avatar_btn);
                }

                /* Name */
                var name_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                name_box.halign = Gtk.Align.CENTER;

                var name_lbl = new Gtk.Label (name);
                name_lbl.add_css_class ("title-1");
                name_lbl.ellipsize = Pango.EllipsizeMode.END;
                name_lbl.max_width_chars = 24;
                name_box.append (name_lbl);

                if (is_dm_chat && dm_contact_id > 1) {
                    var edit_name_btn = new Gtk.Button.from_icon_name (
                        "document-edit-symbolic");
                    edit_name_btn.add_css_class ("flat");
                    edit_name_btn.tooltip_text = "Edit contact name";
                    edit_name_btn.clicked.connect (() => {
                        show_edit_contact_name_dialog (dm_contact_id, name_lbl);
                    });
                    name_box.append (edit_name_btn);
                }

                content.append (name_box);

                /* Type + encryption */
                string type_str = chat_type;
                if (encrypted) type_str += " (encrypted)";
                var type_lbl = new Gtk.Label (type_str);
                type_lbl.add_css_class ("dim-label");
                type_lbl.halign = Gtk.Align.CENTER;
                content.append (type_lbl);

                /* Invite link for groups/channels */
                if (is_group) {
                    var invite_list = new Gtk.ListBox ();
                    invite_list.selection_mode = Gtk.SelectionMode.NONE;
                    invite_list.add_css_class ("boxed-list");

                    var invite_row = new Adw.ActionRow ();
                    invite_row.title = "Invite Link";
                    invite_row.subtitle = "Share a link or QR code for others to join";
                    invite_row.add_prefix (new Gtk.Image.from_icon_name ("mail-forward-symbolic"));
                    invite_row.activatable = true;
                    invite_row.activated.connect (() => {
                        var dialog = new InviteCodeDialog (rpc, rpc.account_id, chat_id);
                        dialog.present (this);
                    });
                    invite_list.append (invite_row);
                    content.append (invite_list);
                }

                /* Disappearing messages */
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

                var ephem_list = new Gtk.ListBox ();
                ephem_list.selection_mode = Gtk.SelectionMode.NONE;
                ephem_list.add_css_class ("boxed-list");
                ephem_list.append (ephem_row);
                content.append (ephem_list);

                /* Separator */
                content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

                /* Members */
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
                        var add_btn = new Gtk.Button.from_icon_name ("list-add-symbolic");
                        add_btn.tooltip_text = "Add member";
                        add_btn.add_css_class ("flat");
                        add_btn.clicked.connect (() => {
                            add_member_dialog.begin ();
                        });
                        header_box.append (add_btn);
                    }

                    content.append (header_box);

                    members_list = new Gtk.ListBox ();
                    members_list.selection_mode = Gtk.SelectionMode.NONE;
                    members_list.add_css_class ("boxed-list");

                    for (uint i = 0; i < ids.get_length (); i++) {
                        int cid = (int) ids.get_int_element (i);
                        member_contact_ids += cid;
                        var contact_obj = yield rpc.get_contact (cid);
                        if (contact_obj == null) continue;
                        var contact = RpcParsers.parse_contact (cid, contact_obj);
                        if (is_dm_chat && contact.id > 1 && dm_contact == null)
                            dm_contact = contact;

                        var row = build_contact_row (contact);
                        members_list.append (row);
                    }

                    content.append (members_list);
                }

                /* ---- Destructive Actions ---- */
                content.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

                var actions_list = new Gtk.ListBox ();
                actions_list.selection_mode = Gtk.SelectionMode.NONE;
                actions_list.add_css_class ("boxed-list");

                /* Clear History */
                var clear_row = new Adw.ActionRow ();
                clear_row.title = "Clear History";
                // clear_row.subtitle = "Delete all messages";

                var clear_me_btn = new Gtk.Button.with_label ("For Me");
                clear_me_btn.valign = Gtk.Align.CENTER;
                clear_me_btn.add_css_class ("flat");
                clear_me_btn.clicked.connect (() => {
                    confirm_clear_history.begin (false);
                });
                clear_row.add_suffix (clear_me_btn);

                var clear_all_btn = new Gtk.Button.with_label ("For Everyone");
                clear_all_btn.valign = Gtk.Align.CENTER;
                clear_all_btn.add_css_class ("flat");
                clear_all_btn.add_css_class ("error");
                clear_all_btn.clicked.connect (() => {
                    confirm_clear_history.begin (true);
                });
                clear_row.add_suffix (clear_all_btn);

                actions_list.append (clear_row);

                if (is_group) {
                    /* Leave Group */
                    var leave_row = new Adw.ActionRow ();
                    leave_row.title = "Leave Group";
                    leave_row.subtitle = "Stop receiving messages";
                    leave_row.add_prefix (new Gtk.Image.from_icon_name ("system-log-out-symbolic"));
                    leave_row.activatable = true;
                    leave_row.activated.connect (() => {
                        confirm_leave_group.begin ();
                    });
                    actions_list.append (leave_row);

                    /* Disband Group */
                    var disband_row = new Adw.ActionRow ();
                    disband_row.title = "Disband Group";
                    disband_row.subtitle = "Remove all members and delete messages";
                    disband_row.add_prefix (new Gtk.Image.from_icon_name ("edit-delete-symbolic"));
                    disband_row.activatable = true;
                    disband_row.activated.connect (() => {
                        confirm_disband_group.begin ();
                    });
                    actions_list.append (disband_row);
                }

                if (dm_contact != null) {
                    actions_list.append (build_contact_block_row (dm_contact));
                }

                /* Delete for Me */
                var del_row = new Adw.ActionRow ();
                del_row.title = "Delete for Me";
                del_row.subtitle = "Remove from your chat list";
                del_row.add_prefix (new Gtk.Image.from_icon_name ("user-trash-symbolic"));
                del_row.activatable = true;
                del_row.activated.connect (() => {
                    confirm_delete_chat.begin ();
                });
                actions_list.append (del_row);

                content.append (actions_list);

            } catch (Error e) {
                spinner.visible = false;
                var err = new Gtk.Label ("Failed to load: " + e.message);
                err.add_css_class ("dim-label");
                err.wrap = true;
                content.append (err);
            }
        }

        private Adw.ActionRow build_contact_row (Contact contact) {
            var row = contact_row (contact);

            /* Copy email button */
            if (contact.address.length > 0) {
                string addr = contact.address;
                var copy_btn = new Gtk.Button.from_icon_name ("edit-copy-symbolic");
                copy_btn.valign = Gtk.Align.CENTER;
                copy_btn.add_css_class ("flat");
                copy_btn.tooltip_text = "Copy email address";
                copy_btn.clicked.connect (() => {
                    var clipboard = this.get_clipboard ();
                    clipboard.set_text (addr);
                });
                row.add_suffix (copy_btn);
            }

            /* Remove button for groups (not self, contact_id=1 is self) */
            if (is_group && contact.id != 1) {
                int cid = contact.id;
                var remove_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic");
                remove_btn.valign = Gtk.Align.CENTER;
                remove_btn.add_css_class ("flat");
                remove_btn.add_css_class ("error");
                remove_btn.tooltip_text = "Remove from group";
                remove_btn.clicked.connect (() => {
                    remove_member.begin (cid, row);
                });
                row.add_suffix (remove_btn);
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

                var contact_obj = yield rpc.get_contact (contact_id);
                if (contact_obj != null) {
                    var contact = RpcParsers.parse_contact (
                        contact_id, contact_obj);
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

        private async void remove_member (int contact_id, Adw.ActionRow row) {
            try {
                yield rpc.remove_contact_from_chat (chat_id, contact_id);
                members_list.remove (row);
            } catch (Error e) {
                /* show inline error */
                row.subtitle = "Remove failed: " + e.message;
            }
        }

        private async void add_member_dialog () {
            var picker = new ContactPickerDialog (rpc);
            picker.contact_picked.connect ((contact_id, email) => {
                do_add_member.begin (email);
            });
            picker.present (this);
        }

        private async void do_add_member (string email) {
            try {
                int contact_id = yield rpc.get_or_create_contact (email);
                yield rpc.add_contact_to_chat (chat_id, contact_id);

                /* Refresh the member list */
                var contact_obj = yield rpc.get_contact (contact_id);
                if (contact_obj != null && members_list != null) {
                    var contact = RpcParsers.parse_contact (contact_id, contact_obj);
                    var row = build_contact_row (contact);
                    members_list.append (row);
                }
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        /* ---- Destructive action confirmations ---- */

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

        private async void confirm_clear_history (bool for_all) {
            string title = for_all ? "Clear for Everyone" : "Clear History";
            string body = for_all
                ? "Delete all messages for all participants? This cannot be undone."
                : "Delete all messages from your device? This cannot be undone.";
            string action_label = for_all ? "Clear for Everyone" : "Clear";
            confirm_action (this, title, body, "clear", action_label, () => {
                do_clear_history.begin (for_all);
            });
        }

        private async void do_clear_history (bool for_all) {
            try {
                var msg_ids = yield rpc.get_message_ids (chat_id);
                if (msg_ids == null || msg_ids.get_length () == 0) return;

                int[] ids = json_ints (msg_ids);

                if (for_all) {
                    yield rpc.delete_messages_for_all (ids);
                } else {
                    yield rpc.delete_messages (ids);
                }

                chat_changed ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private async void confirm_leave_group () {
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

        private async void confirm_disband_group () {
            confirm_action (this, "Disband Group",
                "Remove all members from \"%s\" and delete all messages? This cannot be undone.".printf (chat_name),
                "disband", "Disband", () => { do_disband_group.begin (); });
        }

        private async void do_disband_group () {
            try {
                /* Remove all members except self */
                foreach (int cid in member_contact_ids) {
                    if (cid != 1) {
                        yield rpc.remove_contact_from_chat (chat_id, cid);
                    }
                }

                /* Delete all messages for everyone */
                var msg_ids = yield rpc.get_message_ids (chat_id);
                if (msg_ids != null && msg_ids.get_length () > 0) {
                    yield rpc.delete_messages_for_all (json_ints (msg_ids));
                }

                /* Leave and delete the chat */
                yield rpc.leave_group (chat_id);
                yield rpc.delete_chat (chat_id);

                chat_deleted (chat_id);
                this.close ();
            } catch (Error e) {
                show_error (this, e.message);
            }
        }

        private async void confirm_delete_chat () {
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
