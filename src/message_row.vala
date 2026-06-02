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
                var quote_btn = new Gtk.Button ();
                quote_btn.add_css_class ("flat");
                quote_btn.add_css_class ("quote-block");

                var quote_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
                if (msg.quote_sender_name != null && msg.quote_sender_name.length > 0) {
                    var q_sender = new Gtk.Label (msg.quote_sender_name);
                    q_sender.add_css_class ("quote-sender");
                    q_sender.halign = Gtk.Align.START;
                    q_sender.xalign = 0;
                    quote_box.append (q_sender);
                }
                var q_text = new Gtk.Label (msg.quote_text);
                q_text.add_css_class ("quote-text");
                q_text.halign = Gtk.Align.START;
                q_text.xalign = 0;
                q_text.ellipsize = Pango.EllipsizeMode.END;
                q_text.max_width_chars = 40;
                q_text.lines = 2;
                quote_box.append (q_text);

                quote_btn.child = quote_box;
                if (msg.quote_msg_id > 0) {
                    int qid = msg.quote_msg_id;
                    quote_btn.clicked.connect (() => {
                        quote_clicked (qid);
                    });
                }
                bubble.append (quote_btn);
            }

            /* File attachment */
            bool has_file = (msg.file_name != null && msg.file_name.length > 0)
                         || (msg.file_path != null && msg.file_path.length > 0);
            if (has_file) {
                bool image_shown = false;

                /* Try to show inline image preview */
                if (msg.file_path != null &&
                    FileUtils.test (msg.file_path, FileTest.EXISTS) &&
                    is_image_file (msg)) {
                    this.is_image = true;
                    try {
                        var pixbuf = new Gdk.Pixbuf.from_file_at_scale (
                            msg.file_path, 400, 400, true);
                        int dw = pixbuf.width;
                        int dh = pixbuf.height;
                        if (dw > 260) {
                            dh = (int) ((double) dh * 260.0 / (double) dw);
                            dw = 260;
                        }
                        var texture = Gdk.Texture.for_pixbuf (pixbuf);
                        var picture = new Gtk.Picture.for_paintable (texture);
                        picture.content_fit = Gtk.ContentFit.CONTAIN;
                        picture.can_shrink = false;
                        picture.set_size_request (dw, dh);
                        picture.add_css_class ("message-image");
                        bubble.append (picture);
                        image_shown = true;
                    } catch (Error e) {
                        stderr.printf ("  -> Image load failed: %s\n", e.message);
                    }
                }

                /* Show attachment indicator if image wasn't shown */
                if (!image_shown) {
                    bubble.append (build_file_indicator (msg));
                }
            }

            /* Message text */
            if (msg.text != null && msg.text.length > 0) {
                var text = new Gtk.Label (msg.text);
                try {
                    string markup = Markdown.format (msg.text);
                    // parse http links inside the html-ized pango text
                    var probe = /<\/?a(\s[^>]*)?>/.replace (markup, -1, 0, "");
                    Pango.AttrList attrs;
                    string parsed;
                    unichar accel;
                    Pango.parse_markup (probe, -1, 0, out attrs, out parsed, out accel);
                    text.set_markup (markup);
                } catch {
                    /* invalid markup — plain text fallback already set */
                }
                text.wrap = true;
                text.wrap_mode = Pango.WrapMode.WORD_CHAR;
                text.halign = Gtk.Align.START;
                text.xalign = 0;
                text.selectable = true;
                text.max_width_chars = 50;
                bubble.append (text);
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
            if (msg.reactions != null && msg.reactions.length > 0) {
                var reactions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                reactions_box.add_css_class ("reaction-bar");
                reactions_box.halign = Gtk.Align.START;

                var parts = msg.reactions.split (",");
                foreach (string part in parts) {
                    var kv = part.split (":", 2);
                    if (kv.length >= 2) {
                        string emoji_str = kv[0];
                        string count_str = kv[1];
                        string label_text = count_str == "1"
                            ? emoji_str
                            : "%s %s".printf (emoji_str, count_str);
                        var badge = new Gtk.Label (label_text);
                        badge.add_css_class ("reaction-badge");
                        reactions_box.append (badge);
                    }
                }

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
                var qbtn = new Gtk.Button ();
                qbtn.add_css_class ("flat");
                qbtn.add_css_class ("quote-block");
                var q = new Gtk.Label (
                    (msg.quote_sender_name != null && msg.quote_sender_name.length > 0
                        ? msg.quote_sender_name + ": " : "") + msg.quote_text);
                q.add_css_class ("quote-text");
                q.halign = Gtk.Align.START;
                q.xalign = 0;
                q.ellipsize = Pango.EllipsizeMode.END;
                q.max_width_chars = 60;
                q.lines = 1;
                qbtn.child = q;
                if (msg.quote_msg_id > 0) {
                    int qid = msg.quote_msg_id;
                    qbtn.clicked.connect (() => { quote_clicked (qid); });
                }
                body.append (qbtn);
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
            }
            if (has_file && !image_shown) {
                var fi = build_file_indicator (msg);
                fi.halign = Gtk.Align.START;
                body.append (fi);
            }

            if (msg.text != null && msg.text.length > 0) {
                var text = new Gtk.Label (msg.text);
                try {
                    string markup = Markdown.format (msg.text);
                    var probe = /<\/?a(\s[^>]*)?>/.replace (markup, -1, 0, "");
                    Pango.AttrList attrs;
                    string parsed;
                    unichar accel;
                    Pango.parse_markup (probe, -1, 0, out attrs, out parsed, out accel);
                    text.set_markup (markup);
                } catch {
                    /* plain text */
                }
                text.wrap = true;
                text.wrap_mode = Pango.WrapMode.WORD_CHAR;
                text.halign = Gtk.Align.START;
                text.xalign = 0;
                text.selectable = true;
                body.append (text);
            }

            /* Reactions */
            if (msg.reactions != null && msg.reactions.length > 0) {
                var reactions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
                reactions_box.add_css_class ("reaction-bar");
                reactions_box.halign = Gtk.Align.START;
                var parts = msg.reactions.split (",");
                foreach (string part in parts) {
                    var kv = part.split (":", 2);
                    if (kv.length >= 2) {
                        string label_text = kv[1] == "1"
                            ? kv[0]
                            : "%s %s".printf (kv[0], kv[1]);
                        var badge = new Gtk.Label (label_text);
                        badge.add_css_class ("reaction-badge");
                        reactions_box.append (badge);
                    }
                }
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
            try {
                var pixbuf = new Gdk.Pixbuf.from_file_at_scale (
                    m.file_path, 260, 200, true);
                int dw = pixbuf.width;
                int dh = pixbuf.height;
                if (dh < 180) {
                    dw = (int) ((double) dw * 180.0 / (double) dh);
                    dh = 180;
                }
                var texture = Gdk.Texture.for_pixbuf (pixbuf);
                var picture = new Gtk.Picture.for_paintable (texture);
                picture.content_fit = Gtk.ContentFit.CONTAIN;
                picture.can_shrink = false;
                picture.add_css_class ("message-image");
                picture.add_css_class ("message-image-irc");
                picture.set_size_request (dw, dh);
                picture.halign = Gtk.Align.START;
                picture.valign = Gtk.Align.START;
                strip.append (picture);
            } catch (Error e) {
                var fi = new Gtk.Label (m.file_name ?? "image");
                fi.add_css_class ("dim-label");
                strip.append (fi);
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

        private static string format_timestamp (int64 ts) {
            if (ts <= 0) return "";
            var dt = new DateTime.from_unix_local (ts);
            return dt.format ("%H:%M");
        }

    }

}
