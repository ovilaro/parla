namespace Dc {

    public class EventHandler : Object {

        private unowned RpcClient rpc;
        private unowned GLib.Application? app = null;
        private bool _listening = false;
        private uint chats_reload_timer = 0;
        private uint messages_reload_timer = 0;

        public int active_chat_id { get; set; default = 0; }

        public signal void chats_reload_fired ();
        public signal void messages_reload_fired ();
        public signal void incoming_msg_received (int acct_id, int chat_id, int msg_id);
        public signal void account_unread_changed (int acct_id);
        public signal void imex_progress (int context_id, int progress);
        public signal void configure_progress (int context_id, int progress,
                                                string? comment);

        public EventHandler (RpcClient rpc) {
            this.rpc = rpc;
        }

        public void set_app (GLib.Application a) { this.app = a; }

        public bool is_listening { get { return _listening; } }

        public async void start () {
            if (_listening) return;
            _listening = true;

            while (rpc.is_connected) {
                try {
                    var ev = yield rpc.get_next_event ();
                    if (ev == null) continue;

                    int ctx = (int) ev.get_int_member ("contextId");

                    var event = ev.get_object_member ("event");
                    if (event == null) continue;

                    string kind = event.get_string_member ("kind");

                    /* ImexProgress / ConfigureProgress can come from a
                       non-current account during account creation. */
                    if (kind == "ImexProgress") {
                        int progress = (int) event.get_int_member ("progress");
                        imex_progress (ctx, progress);
                        continue;
                    }
                    if (kind == "ConfigureProgress") {
                        int progress = (int) event.get_int_member ("progress");
                        string? comment = null;
                        if (event.has_member ("comment") &&
                            !event.get_member ("comment").is_null ()) {
                            comment = event.get_string_member ("comment");
                        }
                        configure_progress (ctx, progress, comment);
                        continue;
                    }

                    if (ctx != rpc.account_id) {
                        dispatch_background (ctx, kind, event);
                        continue;
                    }
                    dispatch (kind, event);
                } catch (Error e) {
                    if (rpc.is_connected) {
                        warning ("Event loop error: %s", e.message);
                        yield nap (1000);
                    }
                }
            }

            _listening = false;
        }

        public void schedule_chats_reload () {
            if (chats_reload_timer > 0) return;
            chats_reload_timer = Timeout.add (150, () => {
                chats_reload_timer = 0;
                chats_reload_fired ();
                return Source.REMOVE;
            });
        }

        public void schedule_messages_reload () {
            if (messages_reload_timer > 0 || active_chat_id <= 0) return;
            messages_reload_timer = Timeout.add (150, () => {
                messages_reload_timer = 0;
                messages_reload_fired ();
                return Source.REMOVE;
            });
        }

        private void dispatch (string kind, Json.Object event) {
            switch (kind) {
            case "IncomingMsg":
                int chat_id = (int) event.get_int_member ("chatId");
                int msg_id = (int) event.get_int_member ("msgId");
                incoming_msg_received (rpc.account_id, chat_id, msg_id);
                break;

            case "MsgsChanged":
                int changed_chat = (int) event.get_int_member ("chatId");
                if (changed_chat == 0 || changed_chat == active_chat_id) {
                    schedule_messages_reload ();
                }
                break;

            case "MsgDelivered":
            case "MsgRead":
            case "MsgFailed":
            case "MsgDeleted":
            case "ReactionsChanged":
                int msg_chat = (int) event.get_int_member ("chatId");
                if (msg_chat == active_chat_id) {
                    schedule_messages_reload ();
                }
                break;

            case "MsgsNoticed":
                int noticed_chat = (int) event.get_int_member ("chatId");
                clear_notifications_for_chat (rpc.account_id, noticed_chat);
                account_unread_changed (rpc.account_id);
                schedule_chats_reload ();
                break;

            case "ChatlistChanged":
            case "ChatlistItemChanged":
            case "ChatModified":
            case "ChatDeleted":
                schedule_chats_reload ();
                break;

            default:
                break;
            }
        }

        /* Events arriving from an account other than the active one. We can't
           touch the visible chat/message lists (they belong to the current
           account), but we still want to notify and keep unread badges fresh. */
        private void dispatch_background (int acct_id, string kind,
                                          Json.Object event) {
            switch (kind) {
            case "IncomingMsg":
                int chat_id = (int) event.get_int_member ("chatId");
                int msg_id = (int) event.get_int_member ("msgId");
                incoming_msg_received (acct_id, chat_id, msg_id);
                break;

            case "MsgsNoticed":
                int noticed_chat = (int) event.get_int_member ("chatId");
                clear_notifications_for_chat (acct_id, noticed_chat);
                account_unread_changed (acct_id);
                break;

            case "ChatlistChanged":
            case "ChatlistItemChanged":
            case "ChatModified":
                account_unread_changed (acct_id);
                break;

            default:
                break;
            }
        }

        public async void send_notification (int acct_id, int chat_id, int msg_id) {
            if (app == null) return;
            try {
                var msg = yield rpc.fetch_message_for (acct_id, msg_id);
                if (msg == null) return;
                if (msg.is_outgoing || msg.is_info) return;

                string title = msg.sender_name ?? msg.sender_address ?? "New message";
                try {
                    var chat_obj = yield rpc.get_full_chat_by_id_for (acct_id, chat_id);
                    if (chat_obj != null && chat_obj.has_member ("name")) {
                        string chat_name = chat_obj.get_string_member ("name");
                        if (chat_name != null && chat_name.length > 0
                            && chat_name != title) {
                            title = "%s (%s)".printf (title, chat_name);
                        }
                    }
                } catch (Error e) { /* fall back to sender */ }

                /* Tag notifications from background accounts so the user can
                   tell which profile they belong to. */
                if (acct_id != rpc.account_id) {
                    try {
                        string? acct_name = yield rpc.get_config ("displayname", acct_id);
                        if (acct_name == null || acct_name.length == 0) {
                            acct_name = yield rpc.get_config ("addr", acct_id);
                        }
                        if (acct_name != null && acct_name.length > 0) {
                            title = "[%s] %s".printf (acct_name, title);
                        }
                    } catch (Error e) { /* fall back to plain title */ }
                }

                string body = (msg.text != null && msg.text.length > 0) ? msg.text
                    : (msg.file_name != null && msg.file_name.length > 0) ? msg.file_name
                    : "New message";

                var n = new GLib.Notification (title);
                n.set_body (body);
                n.set_priority (GLib.NotificationPriority.NORMAL);
                /* Clicking the notification raises the window and opens the
                   chat the message belongs to (see Application.startup). */
                n.set_default_action_and_target_value ("app.open-chat",
                    new Variant ("(ii)", acct_id, chat_id));
                string id = notification_id (acct_id, chat_id);
                app.send_notification (id, n);
            } catch (Error e) {
                warning ("Failed to send notification: %s", e.message);
            }
        }

        public void clear_notifications_for_chat (int acct_id, int chat_id) {
            if (acct_id <= 0 || chat_id <= 0) return;
            withdraw_notification_id (notification_id (acct_id, chat_id));
        }

        public async void reconcile_desktop_notifications () {
            if (app == null || !rpc.is_connected) return;
            try {
                var accounts_node = yield rpc.get_all_accounts ();
                if (accounts_node == null) return;
                var accounts = accounts_node.get_array ();
                for (uint i = 0; i < accounts.get_length (); i++) {
                    int acct_id = (int) accounts.get_object_element (i).get_int_member ("id");
                    if (acct_id <= 0) continue;
                    try { yield reconcile_account_notifications (acct_id); }
                    catch (Error e) { /* unconfigured/removed account */ }
                }
            } catch (Error e) {
                warning ("Failed to reconcile desktop notifications: %s", e.message);
            }
        }

        private static string notification_id (int acct_id, int chat_id) {
            return "dc-chat-%d-%d".printf (acct_id, chat_id);
        }

        private static string legacy_notification_id (int acct_id, int msg_id) {
            return "dc-msg-%d-%d".printf (acct_id, msg_id);
        }

        private void withdraw_notification_id (string id) {
            if (app == null || id.length == 0) return;
            app.withdraw_notification (id);
        }

        private async void reconcile_account_notifications (int acct_id) throws Error {
            var entries = yield rpc.get_chatlist_entries_for (acct_id);
            if (entries == null) return;

            for (uint i = 0; i < entries.get_length (); i++) {
                int chat_id = (int) entries.get_int_element (i);
                clear_notifications_for_chat (acct_id, chat_id);
                yield withdraw_legacy_notifications_for_chat (acct_id, chat_id);
            }
        }

        private async void withdraw_legacy_notifications_for_chat (
                int acct_id, int chat_id) throws Error {
            var msg_ids = yield rpc.get_message_ids_for (acct_id, chat_id);
            if (msg_ids == null) return;
            for (uint i = 0; i < msg_ids.get_length (); i++) {
                int msg_id = (int) msg_ids.get_int_element (i);
                if (msg_id <= 0) continue;
                withdraw_notification_id (legacy_notification_id (acct_id, msg_id));
            }
        }

        private async void nap (uint ms) {
            Timeout.add (ms, nap.callback);
            yield;
        }
    }
}
