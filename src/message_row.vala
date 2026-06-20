namespace Dc {

    internal class ScaledPreviewFrame : Gtk.Widget {
        private int natural_width;
        private int natural_height;
        private Gtk.Widget? _child = null;

        public Gtk.Widget? child {
            get { return _child; }
            set {
                if (_child != null) _child.unparent ();
                _child = value;
                if (_child != null) _child.set_parent (this);
                queue_resize ();
            }
        }

        public ScaledPreviewFrame (int natural_width, int natural_height,
                                   string? css_class = null) {
            Object ();
            this.natural_width = int.max (1, natural_width);
            this.natural_height = int.max (1, natural_height);
            overflow = Gtk.Overflow.HIDDEN;
            if (css_class != null) add_css_class (css_class);
        }

        public override void dispose () {
            if (_child != null) {
                _child.unparent ();
                _child = null;
            }
            base.dispose ();
        }

        public override Gtk.SizeRequestMode get_request_mode () {
            return Gtk.SizeRequestMode.HEIGHT_FOR_WIDTH;
        }

        public override void measure (Gtk.Orientation orientation, int for_size,
                                      out int minimum, out int natural,
                                      out int minimum_baseline,
                                      out int natural_baseline) {
            minimum_baseline = natural_baseline = -1;
            int width = MessageRow.media_size (natural_width);
            int height = MessageRow.media_size (natural_height);
            if (orientation == Gtk.Orientation.HORIZONTAL) {
                minimum = 1;
                natural = width;
                return;
            }

            if (for_size > 0) {
                int h = int.max (1,
                    (int) (((int64) height * for_size + width / 2) / width));
                minimum = natural = h;
            } else {
                minimum = 1;
                natural = height;
            }
        }

        public override void size_allocate (int width, int height, int baseline) {
            if (_child != null) _child.allocate (width, height, baseline, null);
        }

        public override void snapshot (Gtk.Snapshot snapshot) {
            if (_child != null) snapshot_child (_child, snapshot);
        }
    }

    /**
     * A single message bubble in the conversation view.
     * Incoming messages are left-aligned, outgoing messages right-aligned.
     */
    public class MessageRow : Gtk.Box {

        public static MessageStyle style = MessageStyle.BUBBLES;
        public static string? self_display_name = null;
        public static string? self_avatar_path = null;
        private static double media_scale = 1.0;
        private const int ALIGN_LEFT = 0;
        private const int ALIGN_RIGHT = 1;
        private const int ALIGN_CENTER = 2;

        private class MarkdownTableRow {
            public string[] cells;
            public bool header;

            public MarkdownTableRow (string[] cells, bool header = false) {
                this.cells = cells;
                this.header = header;
            }
        }

        private class MarkdownTableBlock {
            public GenericArray<MarkdownTableRow> rows =
                new GenericArray<MarkdownTableRow> ();
            public int[] aligns;

            public MarkdownTableBlock (int columns) {
                aligns = new int[columns];
            }
        }

        public int message_id { get; private set; }
        public bool is_outgoing { get; private set; }

        public signal void quote_clicked (int quoted_msg_id);
        public signal void full_message_requested (int msg_id);

        public static void set_media_scale (int font_size, int system_font_size) {
            media_scale = font_size > 0 && system_font_size > 0
                ? (double) font_size / (double) system_font_size
                : 1.0;
        }

        public static int media_size (int value) {
            return int.max (1, (int) (value * media_scale + 0.5));
        }

        public void highlight () {
            this.add_css_class ("message-new");
            Timeout.add (2000, () => {
                this.remove_css_class ("message-new");
                return Source.REMOVE;
            });
        }

        public MessageRow (Message msg, Message? prev = null,
                           GLib.GenericArray<Message>? trailing_images = null,
                           bool is_image_continuation = false,
                           BubbleAvatarDisplay avatar_display =
                               BubbleAvatarDisplay.NONE,
                           bool avatar_scope_enabled = false) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            this.message_id = msg.id;
            this.is_outgoing = msg.is_outgoing;

            /* Info messages (system notifications) get centered styling */
            if (msg.is_info) {
                build_info_row (msg);
                return;
            }

            if (style == MessageStyle.IRC) {
                build_irc_row (msg, prev, trailing_images, is_image_continuation);
                return;
            }

            bool outgoing = msg.is_outgoing;
            bool show_avatar = should_show_bubble_avatar (
                msg, avatar_display, avatar_scope_enabled);

            /* Margins (applied to this box directly) */
            this.margin_start = 8;
            this.margin_end = 8;
            this.margin_top = 2;
            this.margin_bottom = 2;

            /* Bubble */
            var bubble = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            bubble.add_css_class ("message-bubble");
            bubble.add_css_class (outgoing ? "outgoing" : "incoming");
            bubble.valign = Gtk.Align.START;

            /* Forwarded indicator replaces the plain sender line: it already
               names the forwarder (incoming) or just reads "Forwarded"
               (outgoing / unknown sender). */
            if (msg.is_forwarded) {
                bubble.append (build_forwarded_indicator (msg));
            } else if (!outgoing) {
                string? author = effective_author_name (msg);
                if (author != null) {
                    var sender = new Gtk.Label (author);
                    sender.add_css_class ("message-sender");
                    sender.halign = Gtk.Align.START;
                    sender.xalign = 0;
                    sender.ellipsize = Pango.EllipsizeMode.END;
                    if (msg.sender_address != null && msg.sender_address.length > 0)
                        sender.tooltip_text = msg.sender_address;
                    bubble.append (sender);
                }
            }

            /* Quoted / reply block */
            if (msg.quote_text != null && msg.quote_text.length > 0) {
                bubble.append (build_quote_block (msg, 40, 2));
            }

            append_attachment (bubble, msg, false);

            /* Message text */
            if (msg.text != null && msg.text.length > 0) {
                bubble.append (build_text_widget (msg, 50));
            }

            /* Timestamp + pin indicator + delivery/read tick */
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            footer.halign = Gtk.Align.END;
            if (msg.is_pinned) {
                var pin_icon = new Gtk.Label ("📌");
                pin_icon.add_css_class ("message-time");
                footer.append (pin_icon);
            }
            if (msg.is_edited) {
                footer.append (build_edited_indicator ("Edited"));
            }
            var time_str = format_timestamp (msg.timestamp);
            var time_lbl = new Gtk.Label (time_str);
            time_lbl.add_css_class ("message-time");
            footer.append (time_lbl);

            if (outgoing) {
                var tick = build_tick_indicator (msg);
                if (tick != null) footer.append (tick);
            }
            bubble.append (footer);

            /* Reactions */
            var reactions_box = build_reactions_box (msg);
            if (reactions_box != null) {
                bubble.append (reactions_box);
            }

            /* Alignment: outgoing right, incoming left */
            if (outgoing) {
                var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                spacer.hexpand = true;
                this.append (spacer);
            }
            if (!outgoing && show_avatar) {
                this.append (build_bubble_avatar (msg));
            }
            this.append (bubble);
            if (outgoing && show_avatar) {
                this.append (build_bubble_avatar (msg));
            }
            if (!outgoing) {
                var spacer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                spacer.hexpand = true;
                this.append (spacer);
            }
        }

        private void build_irc_row (Message msg, Message? prev,
                                      GLib.GenericArray<Message>? trailing_images,
                                      bool is_image_continuation) {
            /* Continuation rows in an image strip render as zero-height
               so the leading row of the strip owns all the vertical space. */
            if (is_image_continuation) {
                this.add_css_class ("message-irc");
                this.add_css_class ("message-irc-continuation");
                this.height_request = 0;
                this.visible = false;
                return;
            }

            this.margin_start = 8;
            this.margin_end = 8;
            this.margin_top = 0;
            this.margin_bottom = 0;
            this.spacing = 6;
            this.add_css_class ("message-irc");

            string time_str = format_timestamp (msg.timestamp);
            var time_lbl = new Gtk.Label (time_str);
            time_lbl.add_css_class ("message-time");
            time_lbl.add_css_class ("irc-time");
            time_lbl.valign = Gtk.Align.START;
            time_lbl.xalign = 1;
            time_lbl.visible = time_str.length > 0;
            this.append (time_lbl);

            string sender = effective_sender_name (msg);
            var sender_lbl = new Gtk.Label ("<" + sender + ">");
            sender_lbl.add_css_class ("message-sender");
            sender_lbl.add_css_class (msg.is_outgoing
                ? "message-sender-self" : "message-sender-other");
            sender_lbl.valign = Gtk.Align.START;
            sender_lbl.xalign = 0;
            sender_lbl.ellipsize = Pango.EllipsizeMode.END;
            this.append (sender_lbl);

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
            body.hexpand = true;

            /* Forwarded marker */
            if (msg.is_forwarded) {
                var fwd = new Gtk.Label ("↪ forwarded");
                fwd.add_css_class ("message-forwarded");
                fwd.halign = Gtk.Align.START;
                fwd.xalign = 0;
                if (msg.sender_address != null && msg.sender_address.length > 0)
                    fwd.tooltip_text = msg.sender_address;
                body.append (fwd);
            }

            /* Quoted / reply block (kept compact) */
            if (msg.quote_text != null && msg.quote_text.length > 0) {
                body.append (build_quote_block (msg, 60, 1));
            }

            append_attachment (body, msg, true, trailing_images);

            if (msg.text != null && msg.text.length > 0) {
                body.append (build_text_widget (msg, -1));
            }

            /* Reactions */
            var reactions_box = build_reactions_box (msg);
            if (reactions_box != null) {
                body.append (reactions_box);
            }

            this.append (body);

            if (msg.is_edited) {
                var edited = build_edited_indicator ("(edited)");
                edited.valign = Gtk.Align.START;
                this.append (edited);
            }

            /* Outgoing tick indicator at the end */
            if (msg.is_outgoing) {
                var tick = build_tick_indicator (msg);
                if (tick != null) {
                    tick.valign = Gtk.Align.START;
                    this.append (tick);
                }
            }
            if (msg.is_pinned) {
                var pin_icon = new Gtk.Label ("📌");
                pin_icon.add_css_class ("message-time");
                pin_icon.valign = Gtk.Align.START;
                this.append (pin_icon);
            }
        }

        private void append_attachment (Gtk.Box box, Message msg, bool irc,
                                        GLib.GenericArray<Message>? trailing_images = null) {
            if (!msg.has_file) return;
            if (msg.has_local_file && msg.is_image_file ()) {
                if (irc) append_irc_images (box, msg, trailing_images);
                else append_bubble_image (box, msg);
                return;
            }
            if (msg.is_video_file ()) {
                box.append (build_video_preview (msg));
                return;
            }
            if (msg.is_audio_file ()) {
                box.append (build_audio_player (msg));
                return;
            }
            var fi = build_file_indicator (msg);
            if (irc) fi.halign = Gtk.Align.START;
            box.append (fi);
        }

        private static bool should_show_bubble_avatar (
                Message msg, BubbleAvatarDisplay display, bool scope_enabled) {
            if (!scope_enabled || msg.is_info) return false;
            switch (display) {
            case BubbleAvatarDisplay.NONE:
                return false;
            case BubbleAvatarDisplay.OTHER:
                return !msg.is_outgoing;
            case BubbleAvatarDisplay.BOTH:
                return true;
            default:
                return false;
            }
        }

        private static Gtk.Widget build_bubble_avatar (Message msg) {
            string text = msg.is_outgoing
                ? ((self_display_name != null && self_display_name.length > 0)
                    ? self_display_name : "me")
                : (msg.sender_name ?? msg.sender_address ?? "?");
            var avatar = new Adw.Avatar (20, text, true);
            avatar.custom_image = load_avatar (msg.is_outgoing
                ? self_avatar_path : msg.sender_avatar_path);
            avatar.add_css_class ("message-avatar");
            avatar.valign = Gtk.Align.END;
            avatar.tooltip_text = text;
            if (msg.is_outgoing) {
                avatar.margin_start = 4;
            } else {
                avatar.margin_end = 4;
            }
            return avatar;
        }

        private static void append_bubble_image (Gtk.Box bubble, Message msg) {
            var image = load_picture (
                msg.file_path, 400, 400, 260, 0);
            if (image == null) bubble.append (build_file_indicator (msg));
            else bubble.append (image);
        }

        private static void append_irc_images (Gtk.Box body, Message msg,
                                               GLib.GenericArray<Message>? trailing_images) {
            var strip = new Gtk.Box (Gtk.Orientation.HORIZONTAL,
                trailing_images != null && trailing_images.length > 0 ? 4 : 0);
            strip.halign = Gtk.Align.START;
            append_irc_image (strip, msg);
            if (trailing_images != null) {
                for (uint i = 0; i < trailing_images.length; i++) {
                    append_irc_image (strip, trailing_images[i]);
                }
            }
            body.append (strip);
        }

        private static void append_irc_image (Gtk.Box strip, Message m) {
            var picture = load_picture (
                m.file_path, 260, 200, 0, 180);
            if (picture != null) {
                picture.add_css_class ("message-image-irc");
                picture.halign = Gtk.Align.START;
                picture.valign = Gtk.Align.START;
                strip.append (picture);
            } else {
                var fi = new Gtk.Label (m.display_file_name ("image"));
                fi.add_css_class ("dim-label");
                strip.append (fi);
            }
        }

        /**
         * Load a file into a Gtk.Picture sized to fit within (max_w, max_h)
         * preserving aspect, then optionally upscaled to (min_w, min_h).
         * Returns null on read failure (and logs to stderr).
         */
        private static Gtk.Widget? load_picture (string path,
                                                  int max_w, int max_h,
                                                  int min_w, int min_h) {
            try {
                int dw, dh;
                if (Gdk.Pixbuf.get_file_info (path, out dw, out dh) == null ||
                    dw <= 0 || dh <= 0) {
                    return null;
                }
                fit_size (ref dw, ref dh, max_w, max_h, min_w, min_h);

                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (
                    path, media_size (dw), media_size (dh), true);
                var texture = texture_from_pixbuf (pixbuf);
                var picture = new Gtk.Picture.for_paintable (texture);
                picture.content_fit = Gtk.ContentFit.CONTAIN;
                picture.can_shrink = true;
                picture.halign = Gtk.Align.FILL;
                picture.valign = Gtk.Align.FILL;

                var frame = new Gtk.AspectFrame (
                    0.0f, 0.0f,
                    (float) pixbuf.width / (float) pixbuf.height,
                    false);
                frame.add_css_class ("message-image");
                frame.overflow = Gtk.Overflow.HIDDEN;
                frame.set_size_request (pixbuf.width, pixbuf.height);
                frame.child = picture;
                frame.halign = Gtk.Align.START;
                frame.valign = Gtk.Align.START;
                return frame;
            } catch (Error e) {
                stderr.printf ("  -> Image load failed: %s\n", e.message);
                return null;
            }
        }

        private static void fit_size (ref int dw, ref int dh,
                                      int max_w, int max_h,
                                      int min_w, int min_h) {
            if (min_w > 0 && dw < min_w) {
                dh = (int) ((double) dh * min_w / dw); dw = min_w;
            } else if (max_w > 0 && dw > max_w) {
                dh = (int) ((double) dh * max_w / dw); dw = max_w;
            }
            if (min_h > 0 && dh < min_h) {
                dw = (int) ((double) dw * min_h / dh); dh = min_h;
            }
        }

        public static bool same_irc_sender (Message a, Message b) {
            if (a.is_info || b.is_info) return false;
            if (a.is_outgoing != b.is_outgoing) return false;
            if (a.is_outgoing) return true;
            string an = a.sender_name ?? "";
            string bn = b.sender_name ?? "";
            return an == bn;
        }

        private static string effective_sender_name (Message msg) {
            if (msg.is_outgoing) {
                if (self_display_name != null && self_display_name.length > 0)
                    return self_display_name;
                return "me";
            }
            string? author = effective_author_name (msg);
            return author ?? "?";
        }

        /**
         * Display name for an incoming message's author. Prefers the overridden
         * sender name (mailing lists, bots, senders not in the group), shown
         * with a leading "~" per Delta Chat convention; otherwise the contact's
         * display name. Returns null when neither is known.
         */
        private static string? effective_author_name (Message msg) {
            if (msg.override_sender_name != null
                && msg.override_sender_name.length > 0) {
                return "~" + msg.override_sender_name;
            }
            if (msg.sender_name != null && msg.sender_name.length > 0) {
                return msg.sender_name;
            }
            return null;
        }

        /**
         * "Forwarded by <author>" for incoming messages where the forwarder is
         * known, otherwise a plain "Forwarded" marker. Delta Chat does not
         * preserve the original author of forwarded content, so the recoverable
         * identity is the forwarder (sender), exposed as the tooltip address.
         */
        private static Gtk.Label build_forwarded_indicator (Message msg) {
            string? author = msg.is_outgoing ? null : effective_author_name (msg);
            var lbl = new Gtk.Label (author != null
                ? "↪ Forwarded by " + author
                : "↪ Forwarded");
            lbl.add_css_class ("message-forwarded");
            lbl.halign = Gtk.Align.START;
            lbl.xalign = 0;
            lbl.ellipsize = Pango.EllipsizeMode.END;
            if (!msg.is_outgoing && msg.sender_address != null
                && msg.sender_address.length > 0) {
                lbl.tooltip_text = msg.sender_address;
            }
            return lbl;
        }

        private static Gtk.Label build_edited_indicator (string text) {
            var lbl = new Gtk.Label (text);
            lbl.add_css_class ("message-edited");
            lbl.tooltip_text = "This message was edited";
            return lbl;
        }

        private void build_info_row (Message msg) {
            var label = new Gtk.Label (msg.text ?? "");
            label.add_css_class ("dim-label");
            label.add_css_class ("caption");
            label.hexpand = true;
            label.halign = Gtk.Align.CENTER;
            label.justify = Gtk.Justification.CENTER;
            label.margin_top = 4;
            label.margin_bottom = 4;
            label.wrap = true;
            this.append (label);
        }

        private static Gtk.Widget build_video_preview (Message msg) {
            var overlay = new Gtk.Overlay ();
            overlay.halign = Gtk.Align.START;

            overlay.child = build_video_paintable (msg);

            var play_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            play_box.add_css_class ("message-video-play");
            play_box.halign = Gtk.Align.CENTER;
            play_box.valign = Gtk.Align.CENTER;
            play_box.tooltip_text = "Play video";

            var play = new Gtk.Image.from_icon_name ("media-playback-start-symbolic");
            play.pixel_size = 20;
            play_box.append (play);
            overlay.add_overlay (play_box);

            if (msg.file_name != null && msg.file_name.length > 0) {
                var name = new Gtk.Label (msg.file_name);
                name.add_css_class ("message-video-name");
                name.ellipsize = Pango.EllipsizeMode.MIDDLE;
                name.max_width_chars = 30;
                name.halign = Gtk.Align.START;
                name.valign = Gtk.Align.END;
                name.xalign = 0;
                name.margin_start = 8;
                name.margin_end = 8;
                name.margin_bottom = 6;
                overlay.add_overlay (name);
            }

            var frame = new ScaledPreviewFrame (260, 150, "message-video-frame");
            frame.child = overlay;
            return frame;
        }

        private static Gtk.Widget build_video_paintable (Message msg) {
            Gtk.Picture preview;
            if (msg.has_local_file) {
                var media = Gtk.MediaFile.for_filename (msg.file_path);
                media.pause ();
                preview = new Gtk.Picture.for_paintable (media);
            } else {
                preview = new Gtk.Picture.for_paintable (
                    Gdk.Paintable.empty (260, 150));
            }
            preview.alternative_text = msg.display_file_name ("video");
            preview.can_shrink = true;
            preview.content_fit = Gtk.ContentFit.COVER;
            preview.add_css_class ("message-video-bg");
            return preview;
        }

        private static Gtk.Widget build_audio_player (Message msg) {
            if (!msg.has_local_file)
                return build_file_indicator (msg);
            return new AudioPlayer (msg.file_path, msg.file_name);
        }

        private static Gtk.Box build_file_indicator (Message msg) {
            var file_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            file_box.add_css_class ("message-attachment");

            var icon = new Gtk.Image.from_icon_name ("mail-attachment-symbolic");
            icon.pixel_size = 16;
            file_box.append (icon);

            var fname = new Gtk.Label (msg.display_file_name ());
            fname.add_css_class ("dim-label");
            fname.ellipsize = Pango.EllipsizeMode.MIDDLE;
            fname.max_width_chars = 28;
            file_box.append (fname);

            return file_box;
        }

        private static Gtk.Label? build_tick_indicator (Message msg) {
            string glyph;
            string extra_class;
            string? tooltip = null;

            if (msg.is_failed) {
                glyph = "⚠";
                extra_class = "message-tick-failed";
                tooltip = "Sending failed";
            } else if (msg.is_read) {
                glyph = "✓✓";
                extra_class = "message-tick-read";
                tooltip = "Read";
            } else if (msg.is_delivered) {
                glyph = "✓";
                extra_class = "message-tick";
                tooltip = "Delivered";
            } else if (msg.is_pending) {
                glyph = "⧖";
                extra_class = "message-tick";
                tooltip = "Sending…";
            } else {
                return null;
            }

            var lbl = new Gtk.Label (glyph);
            lbl.add_css_class ("message-time");
            lbl.add_css_class (extra_class);
            if (tooltip != null) lbl.tooltip_text = tooltip;
            return lbl;
        }

        private Gtk.Button build_quote_block (Message msg,
                                               int max_width_chars, int lines) {
            var btn = new Gtk.Button ();
            btn.add_css_class ("flat");
            btn.add_css_class ("quote-block");
            if (msg.quote_msg_id > 0) {
                int qid = msg.quote_msg_id;
                btn.clicked.connect (() => { quote_clicked (qid); });
            }
            bool stacked = lines > 1
                && msg.quote_sender_name != null && msg.quote_sender_name.length > 0;
            if (stacked) {
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
                var s = new Gtk.Label (msg.quote_sender_name);
                s.add_css_class ("quote-sender");
                s.halign = Gtk.Align.START; s.xalign = 0;
                box.append (s);
                var t = new Gtk.Label (msg.quote_text);
                t.add_css_class ("quote-text");
                t.halign = Gtk.Align.START; t.xalign = 0;
                t.ellipsize = Pango.EllipsizeMode.END;
                t.max_width_chars = max_width_chars; t.lines = lines;
                box.append (t);
                btn.child = box;
            } else {
                string prefix = msg.quote_sender_name != null
                    && msg.quote_sender_name.length > 0
                    ? msg.quote_sender_name + ": " : "";
                var t = new Gtk.Label (prefix + msg.quote_text);
                t.add_css_class ("quote-text");
                t.halign = Gtk.Align.START; t.xalign = 0;
                t.ellipsize = Pango.EllipsizeMode.END;
                t.max_width_chars = max_width_chars; t.lines = lines;
                btn.child = t;
            }
            return btn;
        }

        /** Message body widget with markdown + link markup. Shared by both row styles. */
        private Gtk.Widget build_text_widget (Message msg, int max_width_chars) {
            Gtk.Widget body;
            if (Markdown.enabled) {
                var table_body = build_text_with_tables (msg.text, max_width_chars);
                body = table_body ?? build_markup_label (msg.text, max_width_chars,
                    is_single_emoji_text (msg.text));
            } else {
                body = build_markup_label (msg.text, max_width_chars,
                    is_single_emoji_text (msg.text));
            }

            if (!msg.has_full_message_action && !msg.is_downloading_full_message) return body;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            box.halign = Gtk.Align.FILL;
            box.append (body);

            if (msg.is_downloading_full_message) {
                var status = new Gtk.Label ("Downloading full message...");
                status.add_css_class ("message-full-text-status");
                status.halign = Gtk.Align.START;
                status.xalign = 0;
                box.append (status);
            } else {
                var btn = new Gtk.Button.with_label (
                    msg.can_download_full_message
                        ? "Download full message"
                        : "Show full message");
                btn.add_css_class ("flat");
                btn.add_css_class ("message-full-text-button");
                btn.halign = Gtk.Align.START;
                btn.clicked.connect (() => {
                    full_message_requested (msg.id);
                });
                box.append (btn);
            }
            return box;
        }

        private static Gtk.Label build_markup_label (string raw,
                                                     int max_width_chars,
                                                     bool big_emoji = false) {
            var text = new Gtk.Label (raw);
            try {
                string markup = Markdown.format (raw);
                var probe = /<\/?a(\s[^>]*)?>/.replace (markup, -1, 0, "");
                Pango.AttrList attrs;
                string parsed;
                unichar accel;
                Pango.parse_markup (probe, -1, 0, out attrs, out parsed, out accel);
                text.set_markup (markup);
            } catch { /* fallback: plain text already in label */ }
            text.wrap = true;
            text.wrap_mode = Pango.WrapMode.WORD_CHAR;
            text.halign = Gtk.Align.START; text.xalign = 0;
            text.selectable = true;
            if (big_emoji) text.add_css_class ("message-big-emoji");
            if (max_width_chars > 0) text.max_width_chars = max_width_chars;
            connect_label_links (text);
            return text;
        }

        private static void connect_label_links (Gtk.Label text) {
            /* Delta Chat invite links join in-app instead of bouncing through a
               browser; everything else falls through to the default handler. */
            text.activate_link.connect ((uri) => {
                if (is_delta_invite_uri (uri) && text.get_root () is Dc.Window) {
                    ((Dc.Window) text.get_root ()).handle_invite_uri (uri);
                    return true;
                }
                return false;
            });
        }

        private static Gtk.Widget? build_text_with_tables (string raw,
                                                           int max_width_chars) {
            var lines = raw.split ("\n");
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            body.halign = Gtk.Align.FILL;
            body.hexpand = true;

            bool found_table = false;
            bool in_code_block = false;
            int text_start = 0;
            for (int i = 0; i < lines.length;) {
                if (is_code_fence_line (lines[i])) {
                    in_code_block = !in_code_block;
                    i++;
                    continue;
                }
                if (in_code_block) {
                    i++;
                    continue;
                }

                int end;
                MarkdownTableBlock? table = parse_table_at (lines, i, out end);
                if (table == null) {
                    i++;
                    continue;
                }

                append_text_block (body, lines, text_start, i, max_width_chars);
                body.append (build_table_grid (table, max_width_chars));
                found_table = true;
                i = end;
                text_start = i;
            }

            if (!found_table) return null;
            append_text_block (body, lines, text_start, lines.length,
                               max_width_chars);
            return body;
        }

        private static bool is_code_fence_line (string line) {
            return line.strip ().has_prefix ("```");
        }

        private static void append_text_block (Gtk.Box body, string[] lines,
                                               int start, int end,
                                               int max_width_chars) {
            string text = join_lines (lines, start, end).strip ();
            if (text.length == 0) return;
            body.append (build_markup_label (text, max_width_chars));
        }

        private static string join_lines (string[] lines, int start, int end) {
            var sb = new StringBuilder ();
            for (int i = start; i < end; i++) {
                if (i > start) sb.append_c ('\n');
                sb.append (lines[i]);
            }
            return sb.str;
        }

        private static MarkdownTableBlock? parse_table_at (string[] lines,
                                                           int start,
                                                           out int end) {
            end = start;
            if (start + 1 >= lines.length) return null;

            string[]? header = parse_table_row (lines[start]);
            string[]? separator = parse_table_row (lines[start + 1]);
            if (header == null || separator == null) return null;
            if (header.length < 2 || header.length != separator.length) return null;
            if (!is_table_separator (separator)) return null;

            var table = new MarkdownTableBlock (header.length);
            for (int c = 0; c < header.length; c++) {
                table.aligns[c] = table_separator_align (separator[c]);
            }
            table.rows.add (new MarkdownTableRow (header, true));

            end = start + 2;
            while (end < lines.length) {
                string line = lines[end];
                if (line.strip ().length == 0) break;

                string[]? cells = parse_table_row (line);
                if (cells == null || cells.length != header.length) break;
                table.rows.add (new MarkdownTableRow (cells));
                end++;
            }

            return table;
        }

        private static string[]? parse_table_row (string line) {
            string trimmed = line.strip ();
            if (!trimmed.contains ("|")) return null;

            string inner = trimmed;
            if (inner.has_prefix ("|")) {
                inner = inner.substring (1);
            }
            if (inner.has_suffix ("|") && inner.length > 0) {
                inner = inner.substring (0, inner.length - 1);
            }

            var raw = inner.split ("|");
            if (raw.length < 2) return null;

            string[] cells = new string[raw.length];
            for (int i = 0; i < raw.length; i++) {
                cells[i] = raw[i].strip ();
            }
            return cells;
        }

        private static bool is_table_separator (string[] cells) {
            foreach (string cell in cells) {
                string s = cell.strip ();
                int start = s.has_prefix (":") ? 1 : 0;
                int end = s.has_suffix (":") ? s.length - 1 : s.length;
                if (end - start < 3) return false;
                for (int i = start; i < end; i++) {
                    if (s[i] != '-') return false;
                }
            }
            return true;
        }

        private static int table_separator_align (string cell) {
            string s = cell.strip ();
            bool left = s.has_prefix (":");
            bool right = s.has_suffix (":");
            if (left && right) return ALIGN_CENTER;
            if (right) return ALIGN_RIGHT;
            return ALIGN_LEFT;
        }

        private static Gtk.Widget build_table_grid (MarkdownTableBlock table,
                                                    int max_width_chars) {
            var grid = new Gtk.Grid ();
            grid.add_css_class ("markdown-table");
            grid.halign = Gtk.Align.FILL;
            grid.hexpand = true;
            grid.column_spacing = 0;
            grid.row_spacing = 0;

            int columns = table.aligns.length;
            int cell_width = table_cell_width_chars (columns, max_width_chars);

            for (int r = 0; r < table.rows.length; r++) {
                var row = table.rows[r];
                for (int c = 0; c < columns; c++) {
                    var cell = build_table_cell (row.cells[c], cell_width,
                                                 table.aligns[c], row.header);
                    grid.attach (cell, c, r, 1, 1);
                }
            }

            return grid;
        }

        private static int table_cell_width_chars (int columns,
                                                   int max_width_chars) {
            int total = max_width_chars > 0 ? max_width_chars : 84;
            int width = (total - ((columns - 1) * 3)) / columns;
            return int.max (6, int.min (28, width));
        }

        private static Gtk.Widget build_table_cell (string raw, int width_chars,
                                                    int align, bool header) {
            var label = build_markup_label (raw, width_chars);
            label.add_css_class ("markdown-table-cell");
            if (header) label.add_css_class ("markdown-table-header");
            label.valign = Gtk.Align.START;
            label.hexpand = true;
            label.width_chars = int.min (width_chars, 18);
            label.max_width_chars = width_chars;
            label.xalign = align == ALIGN_RIGHT ? 1.0f
                : align == ALIGN_CENTER ? 0.5f : 0.0f;
            label.justify = align == ALIGN_RIGHT ? Gtk.Justification.RIGHT
                : align == ALIGN_CENTER ? Gtk.Justification.CENTER
                : Gtk.Justification.LEFT;
            return label;
        }

        private static bool is_single_emoji_text (string? raw) {
            if (raw == null) return false;
            string text = raw.strip ();
            if (text.length == 0) return false;

            int index = 0;
            if (!consume_emoji_sequence (text, ref index)) return false;
            return index == text.length;
        }

        private static bool consume_emoji_sequence (string text, ref int index) {
            unichar c;
            if (!text.get_next_char (ref index, out c)) return false;

            if (is_keycap_base (c)) {
                consume_variation_selectors (text, ref index);
                return consume_char (text, ref index, 0x20e3);
            }

            if (is_regional_indicator (c)) {
                if (!text.get_next_char (ref index, out c)) return false;
                return is_regional_indicator (c);
            }

            if (!is_emoji_base (c)) return false;
            consume_emoji_modifiers (text, ref index);

            while (consume_char (text, ref index, 0x200d)) {
                if (!text.get_next_char (ref index, out c)) return false;
                if (!is_emoji_base (c)) return false;
                consume_emoji_modifiers (text, ref index);
            }

            return true;
        }

        private static bool consume_char (string text, ref int index, unichar expected) {
            int next = index;
            unichar c;
            if (!text.get_next_char (ref next, out c)) return false;
            if (c != expected) return false;
            index = next;
            return true;
        }

        private static void consume_emoji_modifiers (string text, ref int index) {
            while (consume_variation_selectors (text, ref index)
                   || consume_emoji_modifier (text, ref index)) {
            }
            consume_tag_sequence (text, ref index);
        }

        private static bool consume_variation_selectors (string text, ref int index) {
            bool consumed = false;
            while (true) {
                int next = index;
                unichar c;
                if (!text.get_next_char (ref next, out c)) return consumed;
                if (c != 0xfe0e && c != 0xfe0f) return consumed;
                index = next;
                consumed = true;
            }
        }

        private static bool consume_emoji_modifier (string text, ref int index) {
            int next = index;
            unichar c;
            if (!text.get_next_char (ref next, out c)) return false;
            if (c < 0x1f3fb || c > 0x1f3ff) return false;
            index = next;
            return true;
        }

        private static void consume_tag_sequence (string text, ref int index) {
            int before = index;
            int next = index;
            unichar c;
            bool has_tag = false;
            while (text.get_next_char (ref next, out c)) {
                if (c < 0xe0020 || c > 0xe007e) break;
                index = next;
                has_tag = true;
            }
            if (has_tag && consume_char (text, ref index, 0xe007f)) return;
            index = before;
        }

        private static bool is_keycap_base (unichar c) {
            return c == 0x23 || c == 0x2a || (c >= 0x30 && c <= 0x39);
        }

        private static bool is_regional_indicator (unichar c) {
            return c >= 0x1f1e6 && c <= 0x1f1ff;
        }

        private static bool is_emoji_base (unichar c) {
            return c == 0x00a9 || c == 0x00ae
                || c == 0x203c || c == 0x2049
                || c == 0x2122 || c == 0x2139
                || (c >= 0x2194 && c <= 0x21aa)
                || c == 0x231a || c == 0x231b || c == 0x2328 || c == 0x23cf
                || (c >= 0x23e9 && c <= 0x23f3)
                || (c >= 0x23f8 && c <= 0x23fa)
                || c == 0x24c2
                || c == 0x25aa || c == 0x25ab || c == 0x25b6 || c == 0x25c0
                || (c >= 0x25fb && c <= 0x25fe)
                || (c >= 0x2600 && c <= 0x27bf)
                || c == 0x2934 || c == 0x2935
                || (c >= 0x2b05 && c <= 0x2b55)
                || c == 0x3030 || c == 0x303d || c == 0x3297 || c == 0x3299
                || (c >= 0x1f000 && c <= 0x1faff);
        }

        /** Reaction badge bar, or null when the message has no reactions. */
        private static Gtk.Box? build_reactions_box (Message msg) {
            if (msg.reactions == null || msg.reactions.length == 0) return null;
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            box.add_css_class ("reaction-bar");
            box.halign = Gtk.Align.START;
            foreach (string part in msg.reactions.split (",")) {
                var kv = part.split (":", 2);
                if (kv.length < 2) continue;
                var badge = new Gtk.Label (kv[1] == "1" ? kv[0] : "%s %s".printf (kv[0], kv[1]));
                badge.add_css_class ("reaction-badge");
                box.append (badge);
            }
            return box;
        }

        private static string format_timestamp (int64 ts) {
            if (ts <= 0) return "";
            var dt = new DateTime.from_unix_local (ts);
            return dt.format ("%H:%M");
        }

    }

}
