namespace Dc {

    /**
     * A single message bubble in the conversation view.
     * Incoming messages are left-aligned, outgoing messages right-aligned.
     */
    public class MessageRow : Gtk.Box {

        public static MessageStyle style = MessageStyle.BUBBLES;
        public static string? self_display_name = null;

        public int message_id { get; private set; }
        public int64 timestamp { get; private set; }
        public bool is_outgoing { get; private set; }
        public string? file_path { get; private set; }
        public string? file_name { get; private set; }
        public string? message_text { get; private set; }
        public int quote_msg_id { get; private set; }
        public bool is_image { get; private set; }

        public signal void quote_clicked (int quoted_msg_id);

        public void highlight () {
            this.add_css_class ("message-new");
            Timeout.add (2000, () => {
                this.remove_css_class ("message-new");
                return Source.REMOVE;
            });
        }

        public MessageRow (Message msg, Message? prev = null,
                           GLib.GenericArray<Message>? trailing_images = null,
                           bool is_image_continuation = false) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            this.message_id = msg.id;
            this.timestamp = msg.timestamp;
            this.is_outgoing = msg.is_outgoing;
            this.file_path = msg.file_path;
            this.file_name = msg.file_name;
            this.message_text = msg.text;
            this.quote_msg_id = msg.quote_msg_id;

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

            /* Margins (applied to this box directly) */
            this.margin_start = 8;
            this.margin_end = 8;
            this.margin_top = 2;
            this.margin_bottom = 2;

            /* Bubble */
            var bubble = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            bubble.add_css_class ("message-bubble");
            bubble.add_css_class (outgoing ? "outgoing" : "incoming");

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
                    if (msg.sender_address != null && msg.sender_address.length > 0)
                        sender.tooltip_text = msg.sender_address;
                    bubble.append (sender);
                }
            }

            /* Quoted / reply block */
            if (msg.quote_text != null && msg.quote_text.length > 0) {
                bubble.append (build_quote_block (msg, 40, 2));
            }

            /* File attachment */
            bool has_file = (msg.file_name != null && msg.file_name.length > 0)
                         || (msg.file_path != null && msg.file_path.length > 0);
            if (has_file) {
                if (msg.file_path != null
                    && FileUtils.test (msg.file_path, FileTest.EXISTS)
                    && is_image_file (msg)) {
                    this.is_image = true;
                    var image = load_picture (msg.file_path, 400, 400, 260, 0);
                    if (image == null) bubble.append (build_file_indicator (msg));
                    else bubble.append (image);
                } else if (is_video_file (msg)) {
                    bubble.append (build_video_preview (msg));
                } else if (is_audio_file (msg)) {
                    bubble.append (build_audio_player (msg));
                } else {
                    bubble.append (build_file_indicator (msg));
                }
            }

            /* Message text */
            if (msg.text != null && msg.text.length > 0) {
                bubble.append (build_text_label (msg, 50));
            }

            /* Timestamp + pin indicator + delivery/read tick */
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            footer.halign = Gtk.Align.END;
            if (msg.is_pinned) {
                var pin_icon = new Gtk.Label ("📌");
                pin_icon.add_css_class ("message-time");
                footer.append (pin_icon);
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
            this.append (bubble);
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

            /* File attachment / image */
            bool has_file = (msg.file_name != null && msg.file_name.length > 0)
                         || (msg.file_path != null && msg.file_path.length > 0);
            bool image_shown = false;
            bool is_img = has_file && msg.file_path != null
                          && FileUtils.test (msg.file_path, FileTest.EXISTS)
                          && is_image_file (msg);

            if (is_img && trailing_images != null && trailing_images.length > 0) {
                /* Multi-image strip: pack this image and the trailing
                   consecutive same-sender image messages side by side. */
                this.is_image = true;
                var strip = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                strip.halign = Gtk.Align.START;
                append_irc_image (strip, msg);
                for (uint i = 0; i < trailing_images.length; i++) {
                    append_irc_image (strip, trailing_images[i]);
                }
                body.append (strip);
                image_shown = true;
            } else if (is_img) {
                this.is_image = true;
                var single = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                single.halign = Gtk.Align.START;
                append_irc_image (single, msg);
                body.append (single);
                image_shown = true;
            } else if (has_file && is_video_file (msg)) {
                body.append (build_video_preview (msg));
                image_shown = true;
            } else if (has_file && is_audio_file (msg)) {
                body.append (build_audio_player (msg));
                image_shown = true;
            }
            if (has_file && !image_shown) {
                var fi = build_file_indicator (msg);
                fi.halign = Gtk.Align.START;
                body.append (fi);
            }

            if (msg.text != null && msg.text.length > 0) {
                body.append (build_text_label (msg, -1));
            }

            /* Reactions */
            var reactions_box = build_reactions_box (msg);
            if (reactions_box != null) {
                body.append (reactions_box);
            }

            this.append (body);

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

        private static void append_irc_image (Gtk.Box strip, Message m) {
            var picture = load_picture (m.file_path, 260, 200, 0, 180);
            if (picture != null) {
                picture.add_css_class ("message-image-irc");
                picture.halign = Gtk.Align.START;
                picture.valign = Gtk.Align.START;
                strip.append (picture);
            } else {
                var fi = new Gtk.Label (m.file_name ?? "image");
                fi.add_css_class ("dim-label");
                strip.append (fi);
            }
        }

        /**
         * Load a file into a Gtk.Picture sized to fit within (max_w, max_h)
         * preserving aspect, then optionally upscaled to (min_w, min_h).
         * Returns null on read failure (and logs to stderr).
         */
        private static Gtk.Picture? load_picture (string path,
                                                  int max_w, int max_h,
                                                  int min_w, int min_h) {
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (path, max_w, max_h, true);
                int dw = pixbuf.width, dh = pixbuf.height;
                if (min_w > 0 && dw < min_w) {
                    dh = (int) ((double) dh * min_w / dw); dw = min_w;
                } else if (max_w > 0 && dw > max_w) {
                    dh = (int) ((double) dh * max_w / dw); dw = max_w;
                }
                if (min_h > 0 && dh < min_h) {
                    dw = (int) ((double) dw * min_h / dh); dh = min_h;
                }
                var texture = Gdk.Texture.for_pixbuf (pixbuf);
                var picture = new Gtk.Picture.for_paintable (texture);
                picture.content_fit = Gtk.ContentFit.CONTAIN;
                picture.can_shrink = false;
                picture.add_css_class ("message-image");
                picture.set_size_request (dw, dh);
                return picture;
            } catch (Error e) {
                stderr.printf ("  -> Image load failed: %s\n", e.message);
                return null;
            }
        }

        public static bool is_image_only_message (Message m) {
            if (m == null || m.is_info) return false;
            if (m.text != null && m.text.strip ().length > 0) return false;
            if (m.file_path == null || m.file_path.length == 0) return false;
            return is_image_file (m);
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
            if (!msg.is_outgoing && msg.sender_address != null
                && msg.sender_address.length > 0) {
                lbl.tooltip_text = msg.sender_address;
            }
            return lbl;
        }

        private void build_info_row (Message msg) {
            var label = new Gtk.Label (msg.text ?? "");
            label.add_css_class ("dim-label");
            label.add_css_class ("caption");
            label.halign = Gtk.Align.CENTER;
            label.margin_top = 4;
            label.margin_bottom = 4;
            label.wrap = true;
            this.append (label);
        }

        public static bool is_image_file (Message msg) {
            if (msg.file_mime != null && msg.file_mime.has_prefix ("image/"))
                return true;
            if (msg.view_type != null) {
                var vt = msg.view_type.down ();
                if (vt == "image" || vt == "gif" || vt == "sticker")
                    return true;
            }
            if (msg.file_path != null) {
                var lower = msg.file_path.down ();
                if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg") ||
                    lower.has_suffix (".png") || lower.has_suffix (".webp") ||
                    lower.has_suffix (".gif") || lower.has_suffix (".bmp") ||
                    lower.has_suffix (".svg"))
                    return true;
            }
            return false;
        }

        public static bool is_video_file (Message msg) {
            if (msg.file_mime != null && msg.file_mime.has_prefix ("video/"))
                return true;
            if (msg.view_type != null && msg.view_type.down () == "video")
                return true;
            if (msg.file_path != null) {
                var lower = msg.file_path.down ();
                if (lower.has_suffix (".mp4") || lower.has_suffix (".m4v") ||
                    lower.has_suffix (".webm") || lower.has_suffix (".mkv") ||
                    lower.has_suffix (".mov") || lower.has_suffix (".avi") ||
                    lower.has_suffix (".ogv") || lower.has_suffix (".3gp") ||
                    lower.has_suffix (".wmv") || lower.has_suffix (".flv"))
                    return true;
            }
            return false;
        }

        public static bool is_audio_file (Message msg) {
            if (msg.file_mime != null && msg.file_mime.has_prefix ("audio/"))
                return true;
            if (msg.view_type != null) {
                var vt = msg.view_type.down ();
                if (vt == "audio" || vt == "voice")
                    return true;
            }
            if (msg.file_path != null) {
                var lower = msg.file_path.down ();
                if (lower.has_suffix (".mp3") || lower.has_suffix (".ogg") ||
                    lower.has_suffix (".oga") || lower.has_suffix (".opus") ||
                    lower.has_suffix (".wav") || lower.has_suffix (".m4a") ||
                    lower.has_suffix (".aac") || lower.has_suffix (".flac") ||
                    lower.has_suffix (".weba") || lower.has_suffix (".amr"))
                    return true;
            }
            return false;
        }

        /**
         * Inline preview for a video attachment: a dark thumbnail-sized card
         * with a centered play glyph and the file name. Purely visual — the
         * click is handled by the conversation view, which opens the
         * fullscreen player (mirrors how images open the image viewer).
         */
        private static Gtk.Widget build_video_preview (Message msg) {
            var overlay = new Gtk.Overlay ();
            overlay.halign = Gtk.Align.START;

            var bg = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            bg.add_css_class ("message-video-bg");
            bg.set_size_request (260, 150);
            overlay.child = bg;

            var play = new Gtk.Image.from_icon_name ("media-playback-start-symbolic");
            play.add_css_class ("message-video-play");
            play.pixel_size = 48;
            play.halign = Gtk.Align.CENTER;
            play.valign = Gtk.Align.CENTER;
            overlay.add_overlay (play);

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
            return overlay;
        }

        /**
         * Inline player for an audio attachment: a play/pause button and the
         * file name. Playback is self-contained — the captured media stream is
         * created lazily on first press and lives as long as the row.
         */
        /**
         * Inline player for an audio attachment: a compact play/stop button
         * (see AudioPlayer). Falls back to a plain attachment row when the
         * file hasn't been downloaded yet.
         */
        private static Gtk.Widget build_audio_player (Message msg) {
            if (msg.file_path == null
                || !FileUtils.test (msg.file_path, FileTest.EXISTS))
                return build_file_indicator (msg);
            return new AudioPlayer (msg.file_path, msg.file_name);
        }

        private static Gtk.Box build_file_indicator (Message msg) {
            var file_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            file_box.add_css_class ("message-attachment");

            var icon = new Gtk.Image.from_icon_name ("mail-attachment-symbolic");
            icon.pixel_size = 16;
            file_box.append (icon);

            var fname = new Gtk.Label (msg.file_name ?? "file");
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

        /** Message body label with markdown + link markup. Shared by both row styles. */
        private static Gtk.Label build_text_label (Message msg, int max_width_chars) {
            var text = new Gtk.Label (msg.text);
            try {
                string markup = Markdown.format (msg.text);
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
            if (max_width_chars > 0) text.max_width_chars = max_width_chars;
            return text;
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
