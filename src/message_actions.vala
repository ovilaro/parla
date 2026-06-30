namespace Dc {

    public class MessageActions : Object {

        private unowned Window window;
        private unowned RpcClient rpc;
        private unowned GLib.ListStore message_store;
        private unowned PinnedMessagesManager pinned;
        private unowned ComposeBar compose_bar;
        private unowned SettingsManager settings;

        public MessageActions (Window window, RpcClient rpc,
                               GLib.ListStore message_store,
                               PinnedMessagesManager pinned,
                               ComposeBar compose_bar,
                               SettingsManager settings) {
            this.window = window;
            this.rpc = rpc;
            this.message_store = message_store;
            this.pinned = pinned;
            this.compose_bar = compose_bar;
            this.settings = settings;
        }

        public void show_context_menu (int msg_id, bool is_outgoing,
                                       double x, double y,
                                       Gtk.Widget parent) {
            var popover = new Gtk.Popover ();
            popover.has_arrow = false;
            popover.set_parent (parent);
            popover.set_pointing_to ({ (int) x, (int) y, 1, 1 });

            var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            vbox.add_css_class ("menu");
            vbox.margin_start = 8;
            vbox.margin_end = 8;
            vbox.margin_top = 8;
            vbox.margin_bottom = 8;

            /* Reactions — first so they are most easily reachable */
            string[] emojis = { "\xf0\x9f\x91\x8d", "\xe2\x9d\xa4\xef\xb8\x8f",
                                 "\xf0\x9f\x98\x82", "\xf0\x9f\x98\xae",
                                 "\xf0\x9f\x98\xa2", "\xf0\x9f\x91\x8e",
                                 "\xf0\x9f\x94\xa5" };
            if (gtk_emoji_chooser_available ()) {
                emojis += "…";
            }
            var msg = find_message (message_store, msg_id);
            var emoji_row1 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            var emoji_row2 = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            for (int i = 0; i < emojis.length; i++) {
                string emoji = emojis[i];
                var btn = new Gtk.Button.with_label (emoji);
                btn.add_css_class ("flat");
                bool is_more = (emoji == "…");
                if (is_more) {
                    btn.tooltip_text = "More emojis…";
                    btn.clicked.connect (() => {
                        popover.popdown ();
                        Idle.add (() => {
                            show_emoji_picker (msg_id, parent, x, y);
                            return Source.REMOVE;
                        });
                    });
                } else {
                    if (has_my_reaction (msg, emoji)) btn.add_css_class ("suggested-action");
                    btn.clicked.connect (() => {
                        popover.popdown ();
                        Idle.add (() => {
                            send_reaction.begin (msg_id, emoji);
                            return Source.REMOVE;
                        });
                    });
                }
                if (i < 4) emoji_row1.append (btn);
                else emoji_row2.append (btn);
            }
            vbox.append (emoji_row1);
            vbox.append (emoji_row2);

            vbox.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            /* Reply + Forward on the same row */
            var reply_forward_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 2);
            reply_forward_row.homogeneous = true;

            reply_forward_row.append (menu_button (popover, "Reply", () => {
                start_replying (msg_id);
            }, true));

            reply_forward_row.append (menu_button (popover, "Forward\u2026", () => {
                start_forwarding (msg_id);
            }, true));

            vbox.append (reply_forward_row);

            /* Pin / Unpin */
            bool msg_is_pinned = pinned.is_pinned (msg_id);
            vbox.append (menu_button (popover,
                msg_is_pinned ? "Unpin from conversation" : "Pin in conversation",
                () => {
                    pinned.toggle_pin (msg_id);
                }));

            /* Save file (for messages with attachments) */
            if (msg != null && msg.file_path != null &&
                msg.file_path.length > 0) {
                string fpath = msg.file_path;
                string? fname = msg.file_name;
                vbox.append (menu_button (popover, "Save file", () => {
                    window.save_attachment.begin (fpath, fname);
                }));
            }

            if (msg != null && msg.can_edit_text) {
                vbox.append (menu_button (popover, "Edit", () => {
                    start_editing (msg_id);
                }));
            }

            vbox.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            vbox.append (menu_button (popover, "Delete…", () => {
                if (is_outgoing) {
                    confirm_delete_options (window, "Delete Message?",
                        "Delete this message from your device only, or from all participants? This cannot be undone.",
                        () => { delete_message.begin (msg_id, false); },
                        () => { delete_message.begin (msg_id, true); });
                } else {
                    confirm_delete_options (window, "Delete Message?",
                        "Delete this message from your device? This cannot be undone.",
                        () => { delete_message.begin (msg_id, false); },
                        null);
                }
            }));

            popover.child = vbox;
            preserve_scroll_until_closed (popover);
            popover.popup ();
        }

        private Gtk.Button menu_button (Gtk.Popover popover, string label,
                                        owned VoidFunc action,
                                        bool hexpand = false) {
            var btn = new Gtk.Button.with_label (label);
            btn.add_css_class ("flat");
            var child = btn.child as Gtk.Label;
            if (child != null) {
                child.xalign = 0;
                child.halign = Gtk.Align.START;
            }
            btn.hexpand = hexpand;
            btn.clicked.connect (() => {
                btn.sensitive = false;
                popover.popdown ();
                Idle.add (() => {
                    action ();
                    return Source.REMOVE;
                });
            });
            return btn;
        }

        private void preserve_scroll_until_closed (Gtk.Popover popover,
                                                   bool idle_unparent = false) {
            var view = window.current_view ();
            double saved_scroll = view != null ? view.get_scroll_value () : 0;
            if (view != null) view.freeze_scroll_handler (1500);
            popover.closed.connect (() => {
                if (view != null) {
                    view.restore_scroll_value (saved_scroll);
                    view.restore_scroll_value_deferred (saved_scroll);
                }
                if (!idle_unparent) {
                    popover.unparent ();
                    return;
                }
                Idle.add (() => {
                    popover.unparent ();
                    return Source.REMOVE;
                });
            });
        }

        private bool has_my_reaction (Message? msg, string emoji) {
            if (msg == null || msg.my_reactions == null) return false;
            foreach (string me in msg.my_reactions.split (",")) {
                if (me == emoji) return true;
            }
            return false;
        }

        public async void send_reaction (int msg_id, string emoji) {
            try {
                var current = find_message (message_store, msg_id);
                if (has_my_reaction (current, emoji)) {
                    yield rpc.send_reaction (msg_id, new string[] {});
                } else {
                    yield rpc.send_reaction (msg_id, new string[] { emoji });
                }
                yield update_row (msg_id);
            } catch (Error e) {
                window.show_toast ("Reaction failed: " + e.message);
            }
        }

        private void show_emoji_picker (int msg_id, Gtk.Widget parent,
                                         double x, double y) {
            var chooser = create_emoji_chooser ();
            if (chooser == null) {
                window.show_toast ("Emoji picker unavailable");
                return;
            }
            chooser.emoji_picked.connect ((emoji) => {
                send_reaction.begin (msg_id, emoji);
            });
            chooser.set_parent (parent);
            chooser.set_pointing_to ({ (int) x, (int) y, 1, 1 });

            preserve_scroll_until_closed (chooser);
            chooser.popup ();
        }

        public async void delete_message (int msg_id, bool for_all) {
            try {
                if (for_all) {
                    yield rpc.delete_messages_for_all (new int[] { msg_id });
                } else {
                    yield rpc.delete_messages (new int[] { msg_id });
                }
                int idx = find_message_index (message_store, msg_id);
                if (idx >= 0) message_store.remove (idx);
            } catch (Error e) {
                window.show_toast ("Delete failed: " + e.message);
            }
        }

        public void start_editing (int msg_id) {
            var m = find_message (message_store, msg_id);
            if (m != null) start_editing_message (m);
        }

        public void start_editing_last () {
            var m = find_last_editable_text_message (message_store);
            if (m != null) start_editing_message (m);
        }

        private void start_editing_message (Message m) {
            compose_bar.begin_edit (m.id, m.text ?? "");
        }

        public void start_replying (int msg_id) {
            var m = find_message (message_store, msg_id);
            if (m != null) {
                string sender = m.is_outgoing ? "You" : (m.sender_name ?? "");
                string preview = m.text ?? "(attachment)";
                compose_bar.begin_reply (msg_id, sender, preview);
            }
        }

        public void start_forwarding (int msg_id) {
            var picker = new ContactPickerDialog (rpc, window.chat_store,
                                                  "Forward To");
            picker.chat_picked.connect ((chat_id) => {
                forward_to_chat.begin (msg_id, chat_id);
            });
            picker.contact_picked.connect ((contact_id, email) => {
                forward_to_contact.begin (msg_id, contact_id, email);
            });
            picker.present (window);
        }

        private async void forward_to_chat (int msg_id, int chat_id) {
            try {
                yield rpc.forward_messages (new int[] { msg_id }, chat_id);
                window.request_reload_chats ();
                window.show_toast ("Message forwarded");
            } catch (Error e) {
                window.show_toast ("Forward failed: " + e.message);
            }
        }

        private async void forward_to_contact (int msg_id, int contact_id,
                                                string email) {
            try {
                int cid = contact_id;
                if (cid <= 0) {
                    cid = yield rpc.get_or_create_contact (email);
                }
                int chat_id = yield rpc.get_or_create_chat_by_contact (cid);
                yield rpc.forward_messages (new int[] { msg_id }, chat_id);
                window.request_reload_chats ();
                window.show_toast ("Message forwarded");
            } catch (Error e) {
                window.show_toast ("Forward failed: " + e.message);
            }
        }

        public async void edit_message (int msg_id, string new_text) {
            try {
                yield rpc.send_edit_request (msg_id, new_text);
                yield update_row (msg_id);
            } catch (Error e) {
                window.show_toast ("Edit failed: " + e.message);
            }
        }

        public async void update_row (int msg_id) {
            try {
                var msg = yield rpc.fetch_message (msg_id);
                if (msg == null) return;
                var view = window.current_view ();
                if (view != null) {
                    view.replace_message (msg_id, msg);
                } else {
                    int idx = find_message_index (message_store, msg_id);
                    if (idx >= 0) {
                        Object[] replacements = { msg };
                        message_store.splice (idx, 1, replacements);
                    }
                }
            } catch (Error e) {
                /* Reaction will appear on next message reload */
            }
        }

        public void handle_double_click (int msg_id, bool is_outgoing,
                                         double x, double y,
                                         Gtk.Widget parent) {
            switch (settings.double_click_action) {
            case 0: /* Reply */
                start_replying (msg_id);
                break;
            case 1: /* React with heart */
                send_reaction.begin (msg_id, "\xe2\x9d\xa4\xef\xb8\x8f");
                break;
            case 2: /* React with thumbsup */
                send_reaction.begin (msg_id, "\xf0\x9f\x91\x8d");
                break;
            case 3: /* Open user profile */
                open_sender_profile.begin (msg_id);
                break;
            case 4: /* Nothing */
                break;
            case 5: /* Open context menu */
                Idle.add (() => {
                    show_context_menu (msg_id, is_outgoing, x, y, parent);
                    return Source.REMOVE;
                });
                return;
            }
            compose_bar.grab_entry_focus ();
        }

        public async void open_sender_profile (int msg_id) {
            var m = find_message (message_store, msg_id);
            if (m == null || m.sender_address == null || m.is_outgoing) return;
            try {
                int contact_id = yield rpc.lookup_contact (m.sender_address);
                if (contact_id <= 0) return;
                int chat_id = yield rpc.get_or_create_chat_by_contact (contact_id);
                if (chat_id > 0) {
                    window.request_reload_chats ();
                    window.select_chat_by_id (chat_id);
                }
            } catch (Error e) {
                window.show_toast ("Could not open profile: " + e.message);
            }
        }
    }
}
