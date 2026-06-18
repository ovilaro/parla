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
        public signal void edit_last_requested ();

        private Gtk.TextView text_view;
        private Gtk.Label placeholder_label;
        private string placeholder_default = "Type a message…";
        private Gtk.Button attach_button;
        private Gtk.MenuButton emoji_button;
        private const string EMOJI_TRIGGER_START_MARK = "parla-emoji-trigger-start";
        private const string EMOJI_TRIGGER_END_MARK = "parla-emoji-trigger-end";
        private Gtk.Button cancel_attach_button;
        private Gtk.Button cancel_edit_button;
        private Gtk.Label reply_label;
        private Gtk.Box reply_bar;
        private Gtk.Box attachment_bar;
        private Gtk.Picture attachment_picture;
        private Gtk.Image attachment_icon;
        private Gtk.Label attachment_name_label;
        private Gtk.Label attachment_meta_label;
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

            reply_bar.append (flat_icon_button (
                "window-close-symbolic", "Cancel reply", cancel_reply, true));

            append (reply_bar);

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

            attachment_bar.append (flat_icon_button (
                "window-close-symbolic", "Remove attachment", clear_attachment, true));

            append (attachment_bar);

            var input_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

            attach_button = flat_icon_button (
                "mail-attachment-symbolic", "Attach file", on_attach_clicked);
            input_row.append (attach_button);

            emoji_button = new Gtk.MenuButton ();
            emoji_button.icon_name = "face-smile-symbolic";
            emoji_button.add_css_class ("flat");
            emoji_button.tooltip_text = "Insert emoji";
            emoji_button.valign = Gtk.Align.CENTER;
            var emoji_chooser = create_emoji_chooser ();
            if (emoji_chooser != null) {
                emoji_chooser.emoji_picked.connect (on_emoji_picked);
                emoji_chooser.closed.connect (() => {
                    GLib.Idle.add (() => {
                        clear_emoji_trigger_marks ();
                        return GLib.Source.REMOVE;
                    });
                });
                emoji_button.popover = emoji_chooser;
            } else {
                emoji_button.sensitive = false;
                emoji_button.tooltip_text = "Emoji picker unavailable";
            }
            input_row.append (emoji_button);

            cancel_attach_button = flat_icon_button (
                "edit-clear-symbolic", "Remove attachment", clear_attachment);
            cancel_attach_button.visible = false;
            input_row.append (cancel_attach_button);

            cancel_edit_button = flat_icon_button (
                "edit-undo-symbolic", "Cancel editing", cancel_edit);
            cancel_edit_button.visible = false;
            input_row.append (cancel_edit_button);

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

            /* A bare TextView reports the height of its last *validated*
               layout, which is computed asynchronously and for the width it
               had at the time. When its width changes (the cancel-edit
               button appearing, a window resize) or multi-line text is set
               programmatically, the surrounding box keeps the stale height
               and the text gets clipped. The view tracks its content height
               in the vadjustment's "upper", so whenever that settles on a
               new value force a revalidation (the measure) and requeue a
               resize — deferred to idle because the value changes during
               allocation. */
            var entry_vadj = new Gtk.Adjustment (0, 0, 0, 0, 0, 0);
            entry_vadj.notify["upper"].connect (() => {
                GLib.Idle.add (() => {
                    int b1, b2, b3, b4;
                    text_view.measure (Gtk.Orientation.VERTICAL,
                                       text_view.get_width (),
                                       out b1, out b2, out b3, out b4);
                    text_view.queue_resize ();
                    return GLib.Source.REMOVE;
                });
            });
            text_view.vadjustment = entry_vadj;

            var key_ctrl = new Gtk.EventControllerKey ();
            key_ctrl.key_pressed.connect (on_entry_key_pressed);
            text_view.add_controller (key_ctrl);
            input_row.append (entry_overlay);

            var send_button = new Gtk.Button.from_icon_name ("go-up-symbolic");
            send_button.add_css_class ("suggested-action");
            send_button.add_css_class ("circular");
            send_button.tooltip_text = "Send message";
            send_button.valign = Gtk.Align.CENTER;
            send_button.clicked.connect (on_send);
            input_row.append (send_button);

            append (input_row);
        }

        private Gtk.Button flat_icon_button (string icon_name, string tooltip,
                                             owned VoidFunc on_click,
                                             bool circular = false) {
            var button = new Gtk.Button.from_icon_name (icon_name);
            button.add_css_class ("flat");
            if (circular) button.add_css_class ("circular");
            button.tooltip_text = tooltip;
            button.valign = Gtk.Align.CENTER;
            button.clicked.connect (() => { on_click (); });
            return button;
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
            bool open_emoji = text == ":" && previous_char_is_colon ();
            text_view.buffer.insert_at_cursor (text, text.length);
            text_view.grab_focus ();
            if (open_emoji) open_emoji_picker_after_typed_colon ();
        }

        private string get_text () {
            Gtk.TextIter start, end;
            text_view.buffer.get_bounds (out start, out end);
            return text_view.buffer.get_text (start, end, false);
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
                    var texture = texture_from_pixbuf (pixbuf);
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
            if (u == 0) return "%s %s".printf (((int64) v).to_string (), units[u]);
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
            placeholder_label.label = placeholder_default;
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
            text_view.buffer.text = "";
            clear_attachment ();
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
            cancel_reply ();
            clear_attachment ();
            editing_msg_id = msg_id;
            text_view.buffer.text = current_text;
            placeholder_label.label = "Edit message…";
            cancel_edit_button.visible = true;
            attach_button.sensitive = false;
            text_view.grab_focus ();
            Gtk.TextIter end_iter;
            text_view.buffer.get_end_iter (out end_iter);
            text_view.buffer.place_cursor (end_iter);
            /* If the message is taller than the space the entry gets, make
               sure the cursor end is on screen. Deferred to idle so the
               text view has validated the new content first. */
            GLib.Idle.add (() => {
                text_view.scroll_mark_onscreen (text_view.buffer.get_insert ());
                return GLib.Source.REMOVE;
            });
        }

        private void cancel_edit () {
            if (editing_msg_id == 0) return;
            editing_msg_id = 0;
            text_view.buffer.text = "";
            placeholder_label.label = placeholder_default;
            cancel_edit_button.visible = false;
            attach_button.sensitive = true;
        }

        public bool has_active_mode () {
            return editing_msg_id != 0 || replying_msg_id != 0
                || pending_file != null;
        }

        public bool entry_has_focus () {
            var root = get_root () as Gtk.Window;
            if (root == null) return false;
            var fw = root.get_focus ();
            return fw != null
                && (fw == text_view || fw.is_ancestor (text_view));
        }

        public void cancel_active_mode () {
            cancel_edit ();
            cancel_reply ();
            clear_attachment ();
        }

        private void on_emoji_picked (string emoji) {
            if (!replace_emoji_trigger (emoji)) {
                text_view.buffer.insert_at_cursor (emoji, emoji.length);
            }
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
            /* The emoji picker is opened by typing a second colon ("::"),
               so it only fires when one is already in front of the cursor. */
            if (is_plain_colon_key (keyval, state) && previous_char_is_colon ()) {
                open_emoji_picker_after_typed_colon ();
                return false;
            }

            if ((keyval == Gdk.Key.Up || keyval == Gdk.Key.KP_Up)
                && (state & (Gdk.ModifierType.SHIFT_MASK
                             | Gdk.ModifierType.CONTROL_MASK
                             | Gdk.ModifierType.ALT_MASK)) == 0
                && text_view.buffer.get_char_count () == 0
                && !has_active_mode ()) {
                edit_last_requested ();
                return true;
            }

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

        private static bool is_plain_colon_key (uint keyval, Gdk.ModifierType state) {
            if (keyval != Gdk.Key.colon) return false;
            var mods = state & (Gdk.ModifierType.CONTROL_MASK
                              | Gdk.ModifierType.ALT_MASK
                              | Gdk.ModifierType.SUPER_MASK
                              | Gdk.ModifierType.META_MASK);
            return mods == 0;
        }

        private bool previous_char_is_colon () {
            Gtk.TextIter cursor;
            Gtk.TextIter selection_start, selection_end;
            if (text_view.buffer.get_selection_bounds (out selection_start,
                                                        out selection_end)) {
                cursor = selection_start;
            } else {
                text_view.buffer.get_iter_at_mark (out cursor,
                                                   text_view.buffer.get_insert ());
            }
            Gtk.TextIter previous = cursor;
            if (!previous.backward_char ()) return false;
            return previous.get_char () == ':';
        }

        private void open_emoji_picker_after_typed_colon () {
            GLib.Idle.add (() => {
                if (emoji_button.get_popover () != null
                    && remember_typed_colon_trigger ()) {
                    emoji_button.popup ();
                }
                return GLib.Source.REMOVE;
            });
        }

        private bool remember_typed_colon_trigger () {
            clear_emoji_trigger_marks ();

            Gtk.TextIter end;
            text_view.buffer.get_iter_at_mark (out end, text_view.buffer.get_insert ());
            Gtk.TextIter start = end;
            if (!start.backward_char () || !start.backward_char ()) return false;
            if (text_view.buffer.get_text (start, end, false) != "::") return false;

            text_view.buffer.create_mark (EMOJI_TRIGGER_START_MARK, start, true);
            text_view.buffer.create_mark (EMOJI_TRIGGER_END_MARK, end, false);
            return true;
        }

        private bool replace_emoji_trigger (string emoji) {
            var start_mark = text_view.buffer.get_mark (EMOJI_TRIGGER_START_MARK);
            var end_mark = text_view.buffer.get_mark (EMOJI_TRIGGER_END_MARK);
            if (start_mark == null || end_mark == null) return false;

            Gtk.TextIter start, end;
            text_view.buffer.get_iter_at_mark (out start, start_mark);
            text_view.buffer.get_iter_at_mark (out end, end_mark);
            if (start.compare (end) >= 0
                || text_view.buffer.get_text (start, end, false) != "::") {
                clear_emoji_trigger_marks ();
                return false;
            }

            text_view.buffer.@delete (ref start, ref end);
            text_view.buffer.insert (ref start, emoji, emoji.length);
            clear_emoji_trigger_marks ();
            return true;
        }

        private void clear_emoji_trigger_marks () {
            var start_mark = text_view.buffer.get_mark (EMOJI_TRIGGER_START_MARK);
            if (start_mark != null) text_view.buffer.delete_mark (start_mark);

            var end_mark = text_view.buffer.get_mark (EMOJI_TRIGGER_END_MARK);
            if (end_mark != null) text_view.buffer.delete_mark (end_mark);
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
