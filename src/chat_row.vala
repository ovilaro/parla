namespace Dc {

    /**
     * A single row in the chat list sidebar.
     * Shows avatar placeholder, chat name, last message preview, time, and unread badge.
     * Can switch between full and compact (avatar-only) presentations.
     */
    public class ChatRow : Gtk.Box {

        public int chat_id { get; private set; }

        private Gtk.Box mid_box;
        private Gtk.Overlay avatar_overlay;
        private Gtk.Label? badge_label = null;
        private Gtk.Label? compact_unread_dot = null;
        private Gtk.Label? compact_unread_count = null;
        private Gtk.Image? compact_pin_icon = null;
        private bool has_unread;
        private bool is_muted;
        private bool is_pinned;
        private bool is_request;
        private int unread_count;
        private bool compact = false;

        public ChatRow (ChatEntry entry) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 10);
            this.chat_id = entry.id;
            this.has_unread = entry.unread_count > 0 && !entry.is_contact_request;
            this.is_muted = entry.is_muted;
            this.is_pinned = entry.is_pinned;
            this.is_request = entry.is_contact_request;
            this.unread_count = entry.unread_count;
            add_css_class ("chat-row");
            margin_start = 8;
            margin_end = 8;
            margin_top = 4;
            margin_bottom = 4;

            /* Avatar circle wrapped in an overlay so we can stick compact-mode
               badge/pin markers on top of it. */
            var avatar = presence_avatar (40, entry.name, entry.avatar_path,
                entry.was_seen_recently, null, "list-presence-avatar-ring");

            avatar_overlay = new Gtk.Overlay ();
            avatar_overlay.child = avatar;
            avatar_overlay.valign = Gtk.Align.CENTER;
            avatar_overlay.halign = Gtk.Align.CENTER;

            /* Compact unread indicator (badge or count) — shown only in compact */
            if (is_request) {
                compact_unread_dot = new Gtk.Label ("!");
                compact_unread_dot.add_css_class ("compact-request-marker");
                compact_unread_dot.halign = Gtk.Align.END;
                compact_unread_dot.valign = Gtk.Align.START;
                compact_unread_dot.visible = false;
                avatar_overlay.add_overlay (compact_unread_dot);
            } else if (has_unread) {
                string txt = unread_count > 99 ? "99+" : unread_count.to_string ();
                compact_unread_count = new Gtk.Label (txt);
                compact_unread_count.add_css_class (
                    is_muted ? "compact-unread-badge-muted" : "compact-unread-badge");
                compact_unread_count.halign = Gtk.Align.END;
                compact_unread_count.valign = Gtk.Align.START;
                compact_unread_count.visible = false;
                avatar_overlay.add_overlay (compact_unread_count);
            }

            /* Compact pin indicator — small bottom-right dot */
            if (is_pinned) {
                compact_pin_icon = new Gtk.Image.from_icon_name ("view-pin-symbolic");
                compact_pin_icon.pixel_size = 12;
                compact_pin_icon.add_css_class ("compact-pin-marker");
                compact_pin_icon.halign = Gtk.Align.END;
                compact_pin_icon.valign = Gtk.Align.END;
                compact_pin_icon.visible = false;
                avatar_overlay.add_overlay (compact_pin_icon);
            }

            append (avatar_overlay);

            /* Middle: name + preview (hidden in compact mode) */
            mid_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            mid_box.hexpand = true;
            mid_box.valign = Gtk.Align.CENTER;

            /* Top row: name + time */
            var top = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            if (has_unread) {
                var dot = new Gtk.Label ("●");
                dot.add_css_class (is_muted ? "unread-dot-muted" : "unread-dot");
                top.append (dot);
            }

            var name_label = new Gtk.Label (entry.name);
            name_label.add_css_class ("heading");
            if (has_unread) {
                name_label.add_css_class ("unread-name");
            }
            name_label.ellipsize = Pango.EllipsizeMode.END;
            name_label.hexpand = true;
            name_label.halign = Gtk.Align.START;
            name_label.xalign = 0;
            top.append (name_label);

            if (is_pinned) {
                var pin_label = new Gtk.Label ("📌");
                pin_label.add_css_class ("dim-label");
                pin_label.add_css_class ("caption");
                top.append (pin_label);
            }

            var time_label = new Gtk.Label (format_time (entry.timestamp));
            time_label.add_css_class ("dim-label");
            time_label.add_css_class ("caption");
            top.append (time_label);

            mid_box.append (top);

            /* Bottom row: preview + badge */
            var bot = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var preview_label = new Gtk.Label (format_preview (entry));
            if (!has_unread) {
                preview_label.add_css_class ("dim-label");
            }
            preview_label.ellipsize = Pango.EllipsizeMode.END;
            preview_label.hexpand = true;
            preview_label.halign = Gtk.Align.START;
            preview_label.xalign = 0;
            preview_label.max_width_chars = 30;
            bot.append (preview_label);

            /* Contact requests get a "Request" label instead of a count badge */
            if (is_request) {
                badge_label = new Gtk.Label ("Request");
                badge_label.add_css_class ("contact-request-badge");
                badge_label.halign = Gtk.Align.END;
                badge_label.valign = Gtk.Align.CENTER;
                bot.append (badge_label);
            } else if (has_unread) {
                badge_label = new Gtk.Label (unread_count.to_string ());
                badge_label.add_css_class (is_muted ? "unread-badge-muted" : "unread-badge");
                badge_label.halign = Gtk.Align.END;
                badge_label.valign = Gtk.Align.CENTER;
                bot.append (badge_label);
            }

            mid_box.append (bot);
            append (mid_box);
        }

        public void set_compact (bool compact) {
            if (this.compact == compact) return;
            this.compact = compact;
            mid_box.visible = !compact;
            avatar_overlay.hexpand = compact;
            if (compact) {
                margin_start = 0;
                margin_end = 0;
                margin_top = 2;
                margin_bottom = 2;
                add_css_class ("chat-row-compact");
            } else {
                margin_start = 8;
                margin_end = 8;
                margin_top = 4;
                margin_bottom = 4;
                remove_css_class ("chat-row-compact");
            }
            if (compact_unread_dot != null) compact_unread_dot.visible = compact;
            if (compact_unread_count != null) compact_unread_count.visible = compact;
            if (compact_pin_icon != null) compact_pin_icon.visible = compact;
        }


        private static string format_preview (ChatEntry entry) {
            string preview = entry.last_message ?? "";
            if (entry.summary_prefix != null && entry.summary_prefix.length > 0) {
                if (preview.length > 0) {
                    return "%s: %s".printf (entry.summary_prefix, preview);
                }
                return entry.summary_prefix;
            }
            return preview;
        }

        private static string format_time (int64 timestamp) {
            if (timestamp <= 0) return "";

            var now = new DateTime.now_local ();
            var dt = new DateTime.from_unix_local (timestamp);

            /* Same day: show time, otherwise show date */
            if (now.get_year () == dt.get_year () &&
                now.get_day_of_year () == dt.get_day_of_year ()) {
                return dt.format ("%H:%M");
            }
            /* This week: show day name */
            int diff = (int) (now.to_unix () - dt.to_unix ());
            if (diff < 7 * 86400) {
                return dt.format ("%a");
            }
            /* Older: show date */
            return dt.format ("%d/%m/%y");
        }
    }

    public class ChatContextMenu : Object {

        private unowned Window window;
        private unowned RpcClient rpc;
        private unowned GLib.ListStore chat_store;

        public ChatContextMenu (Window window, RpcClient rpc,
                                GLib.ListStore chat_store) {
            this.window = window;
            this.rpc = rpc;
            this.chat_store = chat_store;
        }

        public void show (int chat_id, double x, double y, Gtk.Widget parent) {
            bool is_pinned = false;
            bool has_unread = false;
            var entry = find_chat_entry (chat_store, chat_id);
            if (entry != null) {
                is_pinned = entry.is_pinned;
                has_unread = entry.unread_count > 0;
            }

            var popover = new Gtk.Popover ();
            popover.has_arrow = false;
            popover.set_parent (parent);
            popover.set_pointing_to ({ (int) x, (int) y, 1, 1 });

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            box.add_css_class ("menu");

            append_menu_button (box, popover, is_pinned ? "Unpin" : "Pin",
                () => { toggle_pin.begin (chat_id, is_pinned); });
            append_menu_button (box, popover,
                has_unread ? "Mark as read" : "Mark as unread",
                () => { set_unread_state.begin (chat_id, !has_unread); },
                false, has_unread || chat_id != window.current_chat_id);
            append_menu_button (box, popover, "Details…",
                () => { show_info (chat_id); });
            append_menu_button (box, popover, "Delete…",
                () => { confirm_delete.begin (chat_id); }, true);

            popover.child = box;
            popover.closed.connect (() => { popover.unparent (); });
            popover.popup ();
        }

        private static Gtk.Button make_menu_button (string label) {
            var btn = new Gtk.Button.with_label (label);
            btn.add_css_class ("flat");
            ((Gtk.Label) btn.child).xalign = 0;
            ((Gtk.Label) btn.child).halign = Gtk.Align.START;
            return btn;
        }

        private static void append_menu_button (Gtk.Box box,
                                                Gtk.Popover popover,
                                                string label,
                                                owned VoidFunc action,
                                                bool destructive = false,
                                                bool sensitive = true) {
            var btn = make_menu_button (label);
            if (destructive) btn.add_css_class ("menu-destructive");
            btn.sensitive = sensitive;
            btn.clicked.connect (() => {
                popover.popdown ();
                action ();
            });
            box.append (btn);
        }

        private async void toggle_pin (int chat_id, bool currently_pinned) {
            try {
                string visibility = currently_pinned ? "Normal" : "Pinned";
                yield rpc.set_chat_visibility (chat_id, visibility);
                yield window.load_chats ();
            } catch (Error e) {
                window.show_toast ("Failed to update pin: " + e.message);
            }
        }

        private async void set_unread_state (int chat_id, bool unread) {
            try {
                if (unread) {
                    yield rpc.markfresh_chat (chat_id);
                } else {
                    yield rpc.marknoticed_chat (chat_id);
                }
                window.request_reload_chats ();
                window.show_toast (unread ? "Marked unread" : "Marked read");
            } catch (Error e) {
                window.show_toast ("Failed to update unread marker: " + e.message);
            }
        }

        public void show_info (int chat_id) {
            var dialog = new ChatInfoDialog (rpc, chat_id);

            dialog.chat_deleted.connect ((cid) => {
                window.show_toast ("Chat deleted");
                if (window.current_chat_id == cid)
                    window.clear_chat_view ();
                window.request_reload_chats ();
            });

            dialog.chat_changed.connect (() => {
                window.request_reload_chats ();
                if (window.current_chat_id == chat_id)
                    window.request_messages_reload ();
            });

            dialog.contact_blocked.connect ((cid) => {
                window.show_toast ("Contact blocked");
                if (window.current_chat_id == cid)
                    window.clear_chat_view ();
                window.request_reload_chats ();
            });

            dialog.present (window);
        }

        private async void confirm_delete (int chat_id) {
            string chat_name = "this chat";
            var entry = find_chat_entry (chat_store, chat_id);
            if (entry != null) chat_name = entry.name;

            var d = new Adw.AlertDialog (
                "Clear or Delete Chat?",
                "Choose what to do with \"%s\". Clearing for everyone only applies to messages you sent; deleting removes the chat from your list.".printf (chat_name));
            d.add_response ("cancel", "Cancel");
            d.add_response ("clear_me", "Clear for Me");
            d.add_response ("clear_all", "Clear Sent for Everyone");
            d.add_response ("delete_me", "Delete for Me");
            d.set_response_appearance ("clear_me",
                Adw.ResponseAppearance.DESTRUCTIVE);
            d.set_response_appearance ("clear_all",
                Adw.ResponseAppearance.DESTRUCTIVE);
            d.set_response_appearance ("delete_me",
                Adw.ResponseAppearance.DESTRUCTIVE);
            d.default_response = "cancel";
            d.close_response = "cancel";
            d.response.connect ((r) => {
                if (r == "clear_me") do_clear_history.begin (chat_id, false);
                else if (r == "clear_all") do_clear_history.begin (chat_id, true);
                else if (r == "delete_me") do_delete.begin (chat_id);
            });
            d.present (window);
        }

        private async void do_clear_history (int chat_id, bool for_all) {
            try {
                int[] ids = yield chat_message_ids_for_clear (
                    rpc, rpc.account_id, chat_id, for_all);
                if (ids.length > 0) {
                    if (for_all) yield rpc.delete_messages_for_all (ids);
                    else yield rpc.delete_messages (ids);
                } else if (for_all) {
                    window.show_toast ("No sent messages to clear for everyone");
                    return;
                }
                window.show_toast (for_all
                    ? "Sent messages cleared for everyone" : "Chat cleared");
                if (window.current_chat_id == chat_id)
                    window.request_messages_reload ();
                window.request_reload_chats ();
            } catch (Error e) {
                window.show_toast ("Clear failed: " + e.message);
            }
        }

        private async void do_delete (int chat_id) {
            try {
                yield rpc.delete_chat (chat_id);
                window.show_toast ("Chat deleted");
                if (window.current_chat_id == chat_id)
                    window.clear_chat_view ();
                yield window.load_chats ();
            } catch (Error e) {
                window.show_toast ("Delete failed: " + e.message);
            }
        }
    }
}
