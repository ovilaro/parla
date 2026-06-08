namespace Dc {

    /**
     * Compose bar at the bottom of the message view.
     * Contains a text entry, file attach button, and send button.
     */
    public class ComposeBar : Gtk.Box {

        /* When false (default), Return sends and Shift+Return inserts a
           newline. When true, the roles are swapped. */
        public bool shift_enter_sends { get; set; default = false; }

        public signal void send_message (string text, string? file_path, string? file_name, int quote_msg_id);
        public signal void edit_message (int msg_id, string new_text);

        private Gtk.TextView text_view;
        private Gtk.Label placeholder_label;
        private string placeholder_default = "Type a message…";
        private Gtk.Button send_button;
        private Gtk.Button attach_button;
        private Gtk.MenuButton emoji_button;
        private Gtk.Button cancel_attach_button;
        private Gtk.Button cancel_edit_button;
        private Gtk.Button cancel_reply_button;
        private Gtk.Label reply_label;
        private Gtk.Box reply_bar;
        private Gtk.Box attachment_bar;
        private Gtk.Picture attachment_picture;
        private Gtk.Image attachment_icon;
        private Gtk.Label attachment_name_label;
        private Gtk.Label attachment_meta_label;
        private Gtk.Button attachment_close_button;
        private string? pending_file = null;
        private string? pending_file_name = null;
        private bool pending_file_is_temp = false;
        private int editing_msg_id = 0;
        private int replying_msg_id = 0;

        public ComposeBar () {
            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0
            );
            add_css_class ("compose-bar");
            margin_start = 8;
            margin_end = 8;
            margin_top = 6;
            margin_bottom = 6;

            /* Reply indicator bar (hidden by default) */
            reply_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            reply_bar.add_css_class ("reply-bar");
            reply_bar.visible = false;

            reply_label = new Gtk.Label ("");
            reply_label.add_css_class ("reply-label");
            reply_label.halign = Gtk.Align.START;
            reply_label.valign = Gtk.Align.START;
            reply_label.hexpand = true;
            reply_label.xalign = 0;
            reply_label.wrap = true;
            reply_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            reply_label.lines = 3;
            reply_label.ellipsize = Pango.EllipsizeMode.END;
            reply_bar.append (reply_label);

            cancel_reply_button = new Gtk.Button.from_icon_name ("window-close-symbolic");
            cancel_reply_button.add_css_class ("flat");
            cancel_reply_button.add_css_class ("circular");
            cancel_reply_button.tooltip_text = "Cancel reply";
            cancel_reply_button.valign = Gtk.Align.CENTER;
            cancel_reply_button.clicked.connect (cancel_reply);
            reply_bar.append (cancel_reply_button);

            append (reply_bar);

            /* Attachment preview bar (hidden by default). Shows either an
               image preview (when the attached file is an image) or a
               generic icon + filename + mimetype row. */
            attachment_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            attachment_bar.add_css_class ("attachment-bar");
            attachment_bar.visible = false;

            attachment_picture = new Gtk.Picture ();
            attachment_picture.add_css_class ("attachment-preview-image");
            attachment_picture.content_fit = Gtk.ContentFit.COVER;
            attachment_picture.set_size_request (72, 72);
            attachment_picture.can_shrink = true;
            attachment_bar.append (attachment_picture);

            attachment_icon = new Gtk.Image ();
            attachment_icon.add_css_class ("attachment-preview-icon");
            attachment_icon.pixel_size = 36;
            attachment_icon.valign = Gtk.Align.CENTER;
            attachment_bar.append (attachment_icon);

            var attachment_info = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            attachment_info.valign = Gtk.Align.CENTER;
            attachment_info.hexpand = true;

            attachment_name_label = new Gtk.Label ("");
            attachment_name_label.add_css_class ("attachment-preview-name");
            attachment_name_label.halign = Gtk.Align.START;
            attachment_name_label.xalign = 0;
            attachment_name_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            attachment_name_label.max_width_chars = 40;
            attachment_name_label.single_line_mode = true;
            attachment_info.append (attachment_name_label);

            attachment_meta_label = new Gtk.Label ("");
            attachment_meta_label.add_css_class ("attachment-preview-meta");
            attachment_meta_label.halign = Gtk.Align.START;
            attachment_meta_label.xalign = 0;
            attachment_meta_label.ellipsize = Pango.EllipsizeMode.END;
            attachment_info.append (attachment_meta_label);

            attachment_bar.append (attachment_info);

            attachment_close_button = new Gtk.Button.from_icon_name ("window-close-symbolic");
            attachment_close_button.add_css_class ("flat");
            attachment_close_button.add_css_class ("circular");
            attachment_close_button.tooltip_text = "Remove attachment";
            attachment_close_button.valign = Gtk.Align.CENTER;
            attachment_close_button.clicked.connect (clear_attachment);
            attachment_bar.append (attachment_close_button);

            append (attachment_bar);

            /* Input row */
            var input_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            /* Attach button */
            attach_button = new Gtk.Button.from_icon_name ("mail-attachment-symbolic");
            attach_button.add_css_class ("flat");
            attach_button.tooltip_text = "Attach file";
            attach_button.valign = Gtk.Align.CENTER;
            attach_button.clicked.connect (on_attach_clicked);
            input_row.append (attach_button);

            /* Emoji picker button */
            emoji_button = new Gtk.MenuButton ();
            emoji_button.icon_name = "face-smile-symbolic";
            emoji_button.add_css_class ("flat");
            emoji_button.tooltip_text = "Insert emoji";
            emoji_button.valign = Gtk.Align.CENTER;
            var emoji_chooser = create_emoji_chooser ();
            if (emoji_chooser != null) {
                emoji_chooser.emoji_picked.connect (on_emoji_picked);
                emoji_button.popover = emoji_chooser;
            } else {
                emoji_button.sensitive = false;
                emoji_button.tooltip_text = "Emoji picker unavailable";
            }
            input_row.append (emoji_button);

            /* Cancel attachment button (hidden by default) */
            cancel_attach_button = new Gtk.Button.from_icon_name ("edit-clear-symbolic");
            cancel_attach_button.add_css_class ("flat");
            cancel_attach_button.tooltip_text = "Remove attachment";
            cancel_attach_button.valign = Gtk.Align.CENTER;
            cancel_attach_button.visible = false;
            cancel_attach_button.clicked.connect (clear_attachment);
            input_row.append (cancel_attach_button);

            /* Cancel edit button (hidden by default) */
            cancel_edit_button = new Gtk.Button.from_icon_name ("edit-undo-symbolic");
            cancel_edit_button.add_css_class ("flat");
            cancel_edit_button.tooltip_text = "Cancel editing";
            cancel_edit_button.valign = Gtk.Align.CENTER;
            cancel_edit_button.visible = false;
            cancel_edit_button.clicked.connect (cancel_edit);
            input_row.append (cancel_edit_button);

            /* Multi-line text view with paste handler.
               Wrapped in a ScrolledWindow that grows up to a max height,
               and overlaid with a manual placeholder label since
               Gtk.TextView has no built-in placeholder support. */
            text_view = new Gtk.TextView ();
            text_view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            text_view.accepts_tab = false;
            text_view.top_margin = 7;
            text_view.bottom_margin = 3;
            text_view.left_margin = 12;
            text_view.right_margin = 12;
            text_view.pixels_above_lines = 0;
            text_view.pixels_below_lines = 0;
            text_view.pixels_inside_wrap = 0;
            text_view.hexpand = true;
            text_view.vexpand = false;
            text_view.add_css_class ("compose-entry");

            /* Placeholder is anchored to the top with the exact same
               top margin as the text view, so its baseline matches the
               first line of typed text instead of relying on valign. */
            placeholder_label = new Gtk.Label (placeholder_default);
            placeholder_label.add_css_class ("compose-placeholder");
            placeholder_label.halign = Gtk.Align.START;
            placeholder_label.valign = Gtk.Align.START;
            placeholder_label.margin_start = 12;
            placeholder_label.margin_top = 7;
            placeholder_label.can_target = false;
            placeholder_label.ellipsize = Pango.EllipsizeMode.END;

            var entry_overlay = new Gtk.Overlay ();
            entry_overlay.child = text_view;
            entry_overlay.add_overlay (placeholder_label);
            entry_overlay.hexpand = true;
            entry_overlay.valign = Gtk.Align.CENTER;

            text_view.buffer.changed.connect (update_placeholder);
            update_placeholder ();

            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect (on_entry_key_pressed);
            text_view.add_controller (key_ctrl);
            input_row.append (entry_overlay);

            /* Send button */
            send_button = new Gtk.Button.from_icon_name ("go-up-symbolic");
            send_button.add_css_class ("suggested-action");
            send_button.add_css_class ("circular");
            send_button.tooltip_text = "Send message";
            send_button.valign = Gtk.Align.CENTER;
            send_button.clicked.connect (on_send);
            input_row.append (send_button);

            append (input_row);
        }

        public void grab_entry_focus () {
            /* Gtk.TextView does not select text on grab_focus the way
               Gtk.Entry does, so a plain grab_focus is safe here.
               Defer to idle so focus lands after the current event
               (e.g. a global shortcut) has finished dispatching. */
            text_view.grab_focus ();
            GLib.Idle.add (() => {
                text_view.grab_focus ();
                return GLib.Source.REMOVE;
            });
        }

        /* Insert text at the cursor and take focus. Used by the window's
           type-ahead so pressing a key anywhere starts a message. */
        public void type_text (string text) {
            text_view.buffer.insert_at_cursor (text, text.length);
            text_view.grab_focus ();
        }

        public void clear () {
            text_view.buffer.text = "";
            clear_attachment ();
        }

        private string get_text () {
            Gtk.TextIter start, end;
            text_view.buffer.get_bounds (out start, out end);
            return text_view.buffer.get_text (start, end, false);
        }

        private void set_placeholder (string s) {
            placeholder_label.label = s;
        }

        private void update_placeholder () {
            placeholder_label.visible = text_view.buffer.get_char_count () == 0;
        }

        public bool can_accept_attachment () {
            return editing_msg_id == 0;
        }

        public void set_pending_attachment (string file_path, string? file_name = null) {
            pending_file = file_path;
            pending_file_name = file_name ?? Path.get_basename (file_path);
            pending_file_is_temp = false;
            text_view.buffer.text = "";
            populate_attachment_preview (file_path, pending_file_name);
            cancel_attach_button.visible = true;
        }

        private void populate_attachment_preview (string file_path, string file_name) {
            string mime = guess_mime (file_path);
            bool is_image = mime != null && mime.has_prefix ("image/");
            attachment_picture.visible = false;
            attachment_icon.visible = false;
            if (is_image) {
                try {
                    var pixbuf = new Gdk.Pixbuf.from_file_at_scale (
                        file_path, 256, 256, true);
                    var texture = Gdk.Texture.for_pixbuf (pixbuf);
                    attachment_picture.paintable = texture;
                    attachment_picture.visible = true;
                } catch (Error e) {
                    is_image = false;
                }
            }
            if (!is_image) {
                attachment_icon.icon_name = mime_icon_name (mime, file_path);
                attachment_icon.visible = true;
            }
            attachment_name_label.label = file_name;
            string size_str = format_size (file_size_or_zero (file_path));
            attachment_meta_label.label = mime != null
                ? "%s · %s".printf (mime, size_str)
                : size_str;
            attachment_bar.visible = true;
        }

        private static string? guess_mime (string file_path) {
            try {
                var info = GLib.File.new_for_path (file_path).query_info (
                    "standard::content-type",
                    GLib.FileQueryInfoFlags.NONE);
                string? ct = info.get_content_type ();
                if (ct != null) {
                    var mime = GLib.ContentType.get_mime_type (ct);
                    if (mime != null && mime.length > 0) return mime;
                }
            } catch (Error e) {
            }
            return null;
        }

        private static string mime_icon_name (string? mime, string file_path) {
            if (mime != null) {
                if (mime.has_prefix ("video/")) return "video-x-generic-symbolic";
                if (mime.has_prefix ("audio/")) return "audio-x-generic-symbolic";
                if (mime.has_prefix ("image/")) return "image-x-generic-symbolic";
                if (mime == "application/pdf") return "application-pdf-symbolic";
                if (mime.has_prefix ("text/")) return "text-x-generic-symbolic";
                if (mime == "application/zip" || mime == "application/x-tar" ||
                    mime == "application/gzip" || mime == "application/x-7z-compressed" ||
                    mime == "application/x-rar-compressed" ||
                    mime == "application/x-bzip" || mime == "application/x-bzip2")
                    return "package-x-generic-symbolic";
            }
            var lower = file_path.down ();
            if (lower.has_suffix (".pdf")) return "application-pdf-symbolic";
            if (lower.has_suffix (".zip") || lower.has_suffix (".tar") ||
                lower.has_suffix (".tgz") || lower.has_suffix (".gz") ||
                lower.has_suffix (".7z") || lower.has_suffix (".rar") ||
                lower.has_suffix (".bz2"))
                return "package-x-generic-symbolic";
            return "mail-attachment-symbolic";
        }

        private static int64 file_size_or_zero (string file_path) {
            try {
                var info = GLib.File.new_for_path (file_path).query_info (
                    "standard::size",
                    GLib.FileQueryInfoFlags.NONE);
                return info.get_size ();
            } catch (Error e) {
                return 0;
            }
        }

        private static string format_size (int64 bytes) {
            if (bytes <= 0) return "—";
            double v = bytes;
            string[] units = { "B", "KB", "MB", "GB" };
            int u = 0;
            while (v >= 1024.0 && u < units.length - 1) {
                v /= 1024.0;
                u++;
            }
            if (u == 0) return "%lld %s".printf ((int64) v, units[u]);
            return "%.1f %s".printf (v, units[u]);
        }

        private void clear_attachment () {
            if (pending_file_is_temp && pending_file != null) {
                try {
                    var f = GLib.File.new_for_path (pending_file);
                    f.@delete ();
                } catch (Error e) {
                }
            }
            pending_file = null;
            pending_file_name = null;
            pending_file_is_temp = false;
            cancel_attach_button.visible = false;
            attachment_bar.visible = false;
            attachment_picture.paintable = null;
            attachment_name_label.label = "";
            attachment_meta_label.label = "";
            set_placeholder (placeholder_default);
        }

        private void on_send () {
            string text = get_text ().strip ();
            if (editing_msg_id > 0) {
                if (text.length == 0) return;
                edit_message (editing_msg_id, text);
                cancel_edit ();
                return;
            }
            if (text.length == 0 && pending_file == null) return;
            int qid = replying_msg_id;
            send_message (text, pending_file, pending_file_name, qid);
            cancel_reply ();
            /* Hand temp-file ownership to the in-flight async RPC. */
            pending_file_is_temp = false;
            clear ();
        }

        public void begin_reply (int msg_id, string sender_name, string preview) {
            cancel_edit ();
            replying_msg_id = msg_id;
            reply_label.label = "%s: %s".printf (sender_name, shorten_preview (preview));
            reply_bar.visible = true;
            text_view.grab_focus ();
        }

        /* Keep at most 3 lines and bound total length so the reply bar
           never explodes when quoting long messages. The label itself
           also wraps + ellipsizes at 3 lines as a hard cap. */
        private static string shorten_preview (string text) {
            string[] lines = text.split ("\n");
            int max_lines = 3;
            int n = (lines.length < max_lines) ? lines.length : max_lines;
            var sb = new StringBuilder ();
            for (int i = 0; i < n; i++) {
                if (i > 0) sb.append_c ('\n');
                sb.append (lines[i]);
            }
            if (lines.length > max_lines) sb.append ("…");
            string result = sb.str;
            int max_chars = 240;
            if (result.char_count () > max_chars) {
                int byte_pos = result.index_of_nth_char (max_chars);
                result = result.substring (0, byte_pos) + "…";
            }
            return result;
        }

        private void cancel_reply () {
            replying_msg_id = 0;
            reply_bar.visible = false;
            reply_label.label = "";
        }

        public void begin_edit (int msg_id, string current_text) {
            cancel_edit ();
            cancel_reply ();
            clear_attachment ();
            editing_msg_id = msg_id;
            text_view.buffer.text = current_text;
            set_placeholder ("Edit message…");
            cancel_edit_button.visible = true;
            attach_button.sensitive = false;
            text_view.grab_focus ();
            Gtk.TextIter end_iter;
            text_view.buffer.get_end_iter (out end_iter);
            text_view.buffer.place_cursor (end_iter);
        }

        private void cancel_edit () {
            if (editing_msg_id == 0) return;
            editing_msg_id = 0;
            text_view.buffer.text = "";
            set_placeholder (placeholder_default);
            cancel_edit_button.visible = false;
            attach_button.sensitive = true;
        }

        /* True while a reply, edit or pending attachment is staged. */
        public bool has_active_mode () {
            return editing_msg_id != 0 || replying_msg_id != 0
                || pending_file != null;
        }

        /* Drop whichever of reply/edit/attachment is active and return to
           the plain input prompt. Each helper guards itself, so calling
           all three only clears what is actually set. */
        public void cancel_active_mode () {
            cancel_edit ();
            cancel_reply ();
            clear_attachment ();
        }

        private void on_emoji_picked (string emoji) {
            text_view.buffer.insert_at_cursor (emoji, emoji.length);
            text_view.grab_focus ();
        }

        private void on_attach_clicked () {
            var dialog = new Gtk.FileDialog ();
            dialog.title = "Select file to attach";
            var window = (Gtk.Window) get_root ();
            dialog.open.begin (window, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) {
                        var path = file.get_path ();
                        if (path != null)
                            set_pending_attachment (path, file.get_basename ());
                    }
                } catch (Error e) {
                }
            });
        }

        private bool on_entry_key_pressed (uint keyval, uint keycode,
                                           Gdk.ModifierType state) {
            /* Escape (and dropping the active reply/edit/attachment mode) is
               handled centrally in the window key handler so the two-press
               behavior is consistent. */
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            if (keyval == Gdk.Key.Return
                || keyval == Gdk.Key.KP_Enter
                || keyval == Gdk.Key.ISO_Enter) {
                bool should_send = shift_enter_sends ? shift : !shift;
                if (!should_send) return false; /* let TextView insert a newline */
                on_send ();
                return true;
            }

            if (!can_accept_attachment ()) return false;
            bool primary_v = Platform.has_primary_modifier (state)
                          && (keyval == Gdk.Key.v || keyval == Gdk.Key.V);
            if (!primary_v && !(shift && keyval == Gdk.Key.Insert)) return false;

            var clipboard = get_display ().get_clipboard ();
            var formats = clipboard.get_formats ();
            bool has_files = formats.contain_gtype (typeof (Gdk.FileList));
            bool has_texture = formats.contain_gtype (typeof (Gdk.Texture));
            if (!has_files && !has_texture) return false;
            paste_from_clipboard.begin (clipboard, has_files, has_texture);
            return true;
        }

        /* Browser pastes often expose a FileList with remote URIs or
           stale temp paths; fall back to the clipboard texture in that
           case, saving it as a temp PNG we own. */
        private async void paste_from_clipboard (Gdk.Clipboard clipboard,
                                                 bool try_files, bool try_texture) {
            if (try_files) {
                try {
                    var value = yield clipboard.read_value_async (typeof (Gdk.FileList),
                                                                  Priority.DEFAULT, null);
                    var fl = value == null ? null : (Gdk.FileList?) value.get_boxed ();
                    var gf = fl == null || fl.get_files () == null
                        ? null : fl.get_files ().data;
                    var path = gf == null ? null : gf.get_path ();
                    if (path != null && GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
                        set_pending_attachment (path, gf.get_basename ());
                        return;
                    }
                } catch (Error e) {
                }
            }
            if (!try_texture) return;
            try {
                var texture = yield clipboard.read_texture_async (null);
                if (texture == null) return;
                GLib.FileIOStream stream;
                var tmp = GLib.File.new_tmp ("parla-XXXXXX.png", out stream);
                stream.close ();
                if (texture.save_to_png (tmp.get_path ())) {
                    set_pending_attachment (tmp.get_path (), "pasted-image.png");
                    pending_file_is_temp = true;
                }
            } catch (Error e) {
            }
        }
    }
}
