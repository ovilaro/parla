namespace Dc {

    public delegate void VoidFunc ();

    public static void show_error (Gtk.Widget parent, string message) {
        var d = new Adw.AlertDialog ("Error", message);
        d.add_response ("ok", "OK");
        d.present (parent);
    }

    public static void confirm_action (Gtk.Widget parent, string title,
                                        string body, string action_id,
                                        string action_label,
                                        owned VoidFunc on_confirm) {
        var d = new Adw.AlertDialog (title, body);
        d.add_response ("cancel", "Cancel");
        d.add_response (action_id, action_label);
        d.set_response_appearance (action_id, Adw.ResponseAppearance.DESTRUCTIVE);
        d.default_response = "cancel";
        d.close_response = "cancel";
        d.response.connect ((r) => { if (r == action_id) on_confirm (); });
        d.present (parent);
    }

    public static void confirm_delete_options (Gtk.Widget parent,
                                                string title, string body,
                                                owned VoidFunc on_delete_for_me,
                                                owned VoidFunc? on_delete_for_everyone) {
        var d = new Adw.AlertDialog (title, body);
        d.add_response ("cancel", "Cancel");
        d.add_response ("delete_me", "Delete for Me");
        d.set_response_appearance ("delete_me", Adw.ResponseAppearance.DESTRUCTIVE);
        if (on_delete_for_everyone != null) {
            d.add_response ("delete_all", "Delete for Everyone");
            d.set_response_appearance ("delete_all",
                Adw.ResponseAppearance.DESTRUCTIVE);
        }
        d.default_response = "cancel";
        d.close_response = "cancel";
        d.response.connect ((r) => {
            if (r == "delete_me") on_delete_for_me ();
            else if (r == "delete_all" && on_delete_for_everyone != null)
                on_delete_for_everyone ();
        });
        d.present (parent);
    }

    public static void install_escape_close (Adw.Dialog dialog) {
        var kc = new Gtk.EventControllerKey ();
        kc.propagation_phase = Gtk.PropagationPhase.CAPTURE;
        kc.key_pressed.connect ((kv, kc, st) => {
            if (kv == Gdk.Key.Escape) { dialog.close (); return true; }
            return false;
        });
        ((Gtk.Widget) dialog).add_controller (kc);
    }

    public static Gdk.Texture? load_avatar (string? path) {
        if (path != null && path.length > 0 &&
            FileUtils.test (path, FileTest.EXISTS)) {
            try {
                return Gdk.Texture.from_filename (path);
            } catch (Error e) { /* fallback */ }
        }
        return null;
    }

    /* ---- JSON helpers ---- */

    public static string? json_str (Json.Object obj, string key) {
        if (!obj.has_member (key)) return null;
        var m = obj.get_member (key);
        if (m == null || m.is_null ()) return null;
        return obj.get_string_member (key);
    }

    public static int64 json_int (Json.Object obj, string key, int64 fallback = 0) {
        if (!obj.has_member (key)) return fallback;
        var m = obj.get_member (key);
        if (m == null || m.is_null ()) return fallback;
        return obj.get_int_member (key);
    }

    public static bool json_bool (Json.Object obj, string key) {
        if (!obj.has_member (key)) return false;
        var m = obj.get_member (key);
        if (m == null || m.is_null ()) return false;
        return obj.get_boolean_member (key);
    }

    /* ---- Widget helpers ---- */

    public static void clear_listbox (Gtk.ListBox lb) {
        Gtk.ListBoxRow? row;
        while ((row = lb.get_row_at_index (0)) != null) {
            lb.remove (row);
        }
    }

    public static async string? pick_image_file (Gtk.Window parent, string title) {
        var chooser = new Gtk.FileDialog ();
        chooser.title = title;
        var filter = new Gtk.FileFilter ();
        filter.add_mime_type ("image/*");
        filter.name = "Images";
        var filters = new ListStore (typeof (Gtk.FileFilter));
        filters.append (filter);
        chooser.filters = filters;
        try {
            var file = yield chooser.open (parent, null);
            if (file != null) return file.get_path ();
        } catch (Error e) { /* cancelled */ }
        return null;
    }

    public static Adw.ActionRow contact_row (Contact c, bool activatable = false) {
        string title = c.display_name.length > 0 ? c.display_name : c.address;
        string subtitle = c.display_name.length > 0 ? c.address : "";
        if (c.is_verified && subtitle.length > 0) subtitle += " (verified)";
        else if (c.is_verified) subtitle = "(verified)";
        if (c.is_blocked && subtitle.length > 0) subtitle += " (blocked)";
        else if (c.is_blocked) subtitle = "(blocked)";

        var row = new Adw.ActionRow ();
        row.use_markup = false;
        row.title = title;
        row.subtitle = subtitle;
        row.activatable = activatable;

        var avatar = new Adw.Avatar (32, title, true);
        avatar.custom_image = load_avatar (c.profile_image);
        row.add_prefix (avatar);
        return row;
    }

    public static Adw.ActionRow chat_pick_row (ChatEntry chat) {
        var row = new Adw.ActionRow ();
        row.use_markup = false;
        row.title = chat.name;
        row.title_lines = 1;
        row.subtitle_lines = 1;
        if (chat.last_message != null && chat.last_message.length > 0) {
            row.subtitle = chat.last_message;
        }
        row.name = chat.id.to_string ();
        row.activatable = true;

        var avatar = new Adw.Avatar (32, chat.name, true);
        avatar.custom_image = load_avatar (chat.avatar_path);
        row.add_prefix (avatar);
        return row;
    }

    public class ChatEntry : Object {
        public int id { get; set; default = 0; }
        public string name { get; set; default = ""; }
        public string? last_message { get; set; default = null; }
        public string? summary_prefix { get; set; default = null; }
        public int64 timestamp { get; set; default = 0; }
        public int unread_count { get; set; default = 0; }
        public string? avatar_path { get; set; default = null; }
        public ChatKind kind { get; set; default = ChatKind.UNKNOWN; }
        public bool is_muted { get; set; default = false; }
        public bool is_contact_request { get; set; default = false; }
        public bool is_pinned { get; set; default = false; }
    }

    public enum ChatKind {
        UNKNOWN = 0,
        DIRECT = 1,
        GROUP = 2;
    }

    /* Delivery state values from deltachat-core that the UI renders. */
    public enum MessageState {
        OUT_PREPARING = 18,
        OUT_PENDING   = 20,
        OUT_FAILED    = 24,
        OUT_DELIVERED = 26,
        OUT_MDN_RCVD  = 28;
    }

    public class Message : Object {
        private const string[] IMAGE_EXTENSIONS = {
            ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".svg"
        };
        private const string[] VIDEO_EXTENSIONS = {
            ".mp4", ".m4v", ".webm", ".mkv", ".mov", ".avi", ".ogv", ".3gp", ".wmv", ".flv"
        };
        private const string[] AUDIO_EXTENSIONS = {
            ".mp3", ".ogg", ".oga", ".opus", ".wav", ".m4a", ".aac", ".flac", ".weba", ".amr"
        };

        public int id { get; set; default = 0; }
        public int chat_id { get; set; default = 0; }
        public string? text { get; set; default = null; }
        public string? sender_address { get; set; default = null; }
        public string? sender_name { get; set; default = null; }
        public string? sender_avatar_path { get; set; default = null; }
        /* True when the message was forwarded into this chat. */
        public bool is_forwarded { get; set; default = false; }
        /* True when the message text was edited after sending. */
        public bool is_edited { get; set; default = false; }
        /* Overridden author name (mailing lists, bots, non-group senders);
           shown with a leading "~" by convention. */
        public string? override_sender_name { get; set; default = null; }
        public int64 timestamp { get; set; default = 0; }
        public bool is_outgoing { get; set; default = false; }
        public string? file_path { get; set; default = null; }
        public string? file_name { get; set; default = null; }
        public string? file_mime { get; set; default = null; }
        public int file_bytes { get; set; default = 0; }
        public string? view_type { get; set; default = null; }
        public bool is_info { get; set; default = false; }
        public bool has_html { get; set; default = false; }
        public string download_state { get; set; default = "Done"; }
        public string? reactions { get; set; default = null; }
        /* Emojis the local user has reacted with (comma-separated). */
        public string? my_reactions { get; set; default = null; }
        public int quote_msg_id { get; set; default = 0; }
        public string? quote_text { get; set; default = null; }
        public string? quote_sender_name { get; set; default = null; }
        public bool is_pinned { get; set; default = false; }
        public bool highlighted { get; set; default = false; }
        public bool selection_visible { get; set; default = false; }
        public bool selected { get; set; default = false; }

        /* Delivery state — one of MessageState. */
        public int state { get; set; default = 0; }

        /* Convenience derived flags for the UI. */
        public bool is_pending {
            get {
                return state == MessageState.OUT_PENDING
                    || state == MessageState.OUT_PREPARING;
            }
        }
        public bool is_delivered {
            get {
                return state == MessageState.OUT_DELIVERED
                    || state == MessageState.OUT_MDN_RCVD;
            }
        }
        public bool is_read {
            get { return state == MessageState.OUT_MDN_RCVD; }
        }
        public bool is_failed {
            get { return state == MessageState.OUT_FAILED; }
        }
        public bool has_text {
            get { return text != null && text.strip ().length > 0; }
        }
        public bool can_download_full_message {
            get { return download_state == "Available" || download_state == "Failure"; }
        }
        public bool is_downloading_full_message {
            get { return download_state == "InProgress"; }
        }
        public bool has_full_message_action {
            get { return can_download_full_message || has_html; }
        }
        public bool can_edit_text {
            get { return is_outgoing && !is_info && has_text; }
        }
        public bool has_file {
            get { return has_value (file_name) || has_value (file_path); }
        }
        public bool has_local_file {
            get { return has_value (file_path) && FileUtils.test (file_path, FileTest.EXISTS); }
        }
        public bool is_image_only {
            get { return !is_info && !has_text && has_value (file_path) && is_image_file (); }
        }

        public bool is_image_file () {
            return has_mime ("image/")
                || view_type_is ("image", "gif", "sticker")
                || path_has_suffix (IMAGE_EXTENSIONS);
        }

        public bool is_video_file () {
            return has_mime ("video/")
                || view_type_is ("video")
                || path_has_suffix (VIDEO_EXTENSIONS);
        }

        public bool is_audio_file () {
            return has_mime ("audio/")
                || view_type_is ("audio", "voice")
                || path_has_suffix (AUDIO_EXTENSIONS);
        }

        public string display_file_name (string fallback = "file") {
            return has_value (file_name) ? file_name : fallback;
        }

        private bool has_value (string? value) {
            return value != null && value.length > 0;
        }

        private bool has_mime (string prefix) {
            return file_mime != null && file_mime.has_prefix (prefix);
        }

        private bool view_type_is (string a, string? b = null, string? c = null) {
            if (view_type == null) return false;
            string vt = view_type.down ();
            return vt == a || (b != null && vt == b) || (c != null && vt == c);
        }

        private bool path_has_suffix (string[] suffixes) {
            if (file_path == null) return false;
            string lower = file_path.down ();
            foreach (string suffix in suffixes) {
                if (lower.has_suffix (suffix)) return true;
            }
            return false;
        }
    }

    public class Contact : Object {
        public int id { get; set; default = 0; }
        public string display_name { get; set; default = ""; }
        public string address { get; set; default = ""; }
        public string? profile_image { get; set; default = null; }
        public bool is_verified { get; set; default = false; }
        public bool is_blocked { get; set; default = false; }
    }

    public ChatEntry? find_chat_entry (GLib.ListStore store, int chat_id) {
        for (uint i = 0; i < store.get_n_items (); i++) {
            var entry = (ChatEntry) store.get_item (i);
            if (entry.id == chat_id) return entry;
        }
        return null;
    }

    public Message? find_message (GLib.ListModel store, int msg_id) {
        for (uint i = 0; i < store.get_n_items (); i++) {
            var m = (Message) store.get_item (i);
            if (m.id == msg_id) return m;
        }
        return null;
    }

    public int find_message_index (GLib.ListModel store, int msg_id) {
        for (uint i = 0; i < store.get_n_items (); i++) {
            var m = (Message) store.get_item (i);
            if (m.id == msg_id) return (int) i;
        }
        return -1;
    }

    public Message? find_last_editable_text_message (GLib.ListStore store) {
        for (uint i = store.get_n_items (); i > 0; i--) {
            var m = (Message) store.get_item (i - 1);
            if (m.can_edit_text) return m;
        }
        return null;
    }
}
