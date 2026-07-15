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

        public void set_natural_size (int width, int height) {
            natural_width = int.max (1, width);
            natural_height = int.max (1, height);
            queue_resize ();
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
                int allocated_width = int.min (for_size, width);
                int h = int.max (1,
                    (int) (((int64) height * allocated_width + width / 2) / width));
                /* The frame must reserve its aspect-ratio height.  A
                   one-pixel minimum lets GtkBox allocate a 1x1 preview,
                   affecting both normal images and stickers. */
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
     * Steps a Gtk.Picture through a Gdk.PixbufAnimation while the picture is
     * mapped. Frame delays come from the animation itself; the timer stops
     * whenever the widget leaves the visible tree, so off-screen stickers
     * cost nothing. Owned by the picture via object data (see
     * MessageRow.load_sticker), which keeps it alive exactly as long as the
     * widget.
     */
    internal class StickerAnimation : Object {
        private Gdk.PixbufAnimation animation;
        private Gdk.PixbufAnimationIter? iter = null;
        private uint timeout_id = 0;
        private unowned Gtk.Picture picture;

        public StickerAnimation (Gtk.Picture picture,
                                 Gdk.PixbufAnimation animation) {
            this.picture = picture;
            this.animation = animation;
            picture.paintable = texture_from_pixbuf (
                animation.get_static_image ());
            picture.map.connect (on_map);
            picture.unmap.connect (on_unmap);
        }

        private void on_map () {
            if (iter == null) iter = animation.get_iter (null);
            show_current_frame ();
            schedule_next_frame ();
        }

        private void on_unmap () {
            if (timeout_id != 0) {
                Source.remove (timeout_id);
                timeout_id = 0;
            }
        }

        private void show_current_frame () {
            picture.paintable = texture_from_pixbuf (iter.get_pixbuf ());
        }

        private void schedule_next_frame () {
            int delay = iter.get_delay_time ();
            if (delay < 0) return; /* single frame or end of animation */
            timeout_id = Timeout.add (int.max (delay, 20), () => {
                iter.advance (null);
                show_current_frame ();
                schedule_next_frame ();
                return Source.REMOVE;
            });
        }
    }

    /**
     * Presents a WebM sticker as a muted, looping media paintable. Playback
     * follows the picture's mapped state so stickers outside the viewport do
     * not consume decoding resources.
     */
    internal class StickerVideoAnimation : Object {
        private Gtk.MediaFile media;
        private unowned Gtk.Picture picture;
        private unowned ScaledPreviewFrame frame;
        private bool animate;
        private int max_size;

        public StickerVideoAnimation (Gtk.Picture picture,
                                      ScaledPreviewFrame frame,
                                      string path,
                                      bool animate,
                                      int max_size) {
            this.picture = picture;
            this.frame = frame;
            this.animate = animate;
            this.max_size = max_size;

            media = Gtk.MediaFile.for_filename (path);
            media.set_loop (true);
            media.set_muted (true);
            picture.paintable = media;

            media.notify["prepared"].connect (update_size);
            update_size ();
            picture.map.connect (on_map);
            picture.unmap.connect (on_unmap);
        }

        private void update_size () {
            int width = media.get_intrinsic_width ();
            int height = media.get_intrinsic_height ();
            if (width <= 0 || height <= 0) return;

            double scale = double.min (1.0, double.min (
                (double) max_size / width,
                (double) max_size / height));
            width = int.max (1, (int) (width * scale + 0.5));
            height = int.max (1, (int) (height * scale + 0.5));
            frame.set_natural_size (width, height);
        }

        private void on_map () {
            if (animate) media.play ();
        }

        private void on_unmap () {
            media.pause ();
        }
    }

    /**
     * A single message bubble in the conversation view.
     * Incoming messages are left-aligned, outgoing messages right-aligned.
     */
    public class MessageRow : Gtk.Box {

        public static MessageStyle style = MessageStyle.BUBBLES;
        public static bool animate_stickers = true;
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

        /* Roster used to turn @name / @address tokens in the body into
           clickable mention links; null in direct chats and when unavailable. */
        private MentionRoster? mention_roster = null;
        private MentionRoster? reaction_roster = null;

        public signal void quote_clicked (int quoted_msg_id);
        public signal void action_requested (string action, Gtk.Widget anchor);
        public signal void full_message_requested (int msg_id);
        public signal void selection_toggled (int msg_id, bool selected);
        public signal void checkbox_toggle_requested (int msg_id, string new_text);

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

        public bool has_selectable_text () {
            return has_selectable_text_in (this);
        }

        public bool select_all_text () {
            bool selected = false;
            bool focused = false;
            select_all_text_in (this, ref selected, ref focused);
            return selected;
        }

        private static bool has_selectable_text_in (Gtk.Widget? widget) {
            if (widget == null) return false;
            var label = widget as Gtk.Label;
            if (label != null && label.selectable &&
                    label.get_text ().length > 0) {
                return true;
            }

            for (Gtk.Widget? child = widget.get_first_child ();
                    child != null;
                    child = child.get_next_sibling ()) {
                if (has_selectable_text_in (child)) return true;
            }
            return false;
        }

        private static void select_all_text_in (Gtk.Widget? widget,
                                                ref bool selected,
                                                ref bool focused) {
            if (widget == null) return;
            var label = widget as Gtk.Label;
            if (label != null && label.selectable &&
                    label.get_text ().length > 0) {
                if (!focused) {
                    label.grab_focus ();
                    focused = true;
                }
                label.select_region (0, -1);
                selected = true;
            }

            for (Gtk.Widget? child = widget.get_first_child ();
                    child != null;
                    child = child.get_next_sibling ()) {
                select_all_text_in (child, ref selected, ref focused);
            }
        }

        public MessageRow (Message msg, Message? prev = null,
                           GLib.GenericArray<Message>? trailing_images = null,
                           bool is_image_continuation = false,
                           BubbleAvatarDisplay avatar_display =
                               BubbleAvatarDisplay.NONE,
                           bool avatar_scope_enabled = false,
                           bool show_sender_name = true,
                           MentionRoster? mention_roster = null,
                           MentionRoster? reaction_roster = null) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 0);
            this.message_id = msg.id;
            this.is_outgoing = msg.is_outgoing;
            this.mention_roster = mention_roster;
            this.reaction_roster = reaction_roster;
            hexpand = true;
            halign = Gtk.Align.FILL;

            if (style == MessageStyle.IRC && is_image_continuation) {
                build_irc_row (msg, trailing_images, true);
                return;
            }

            append_selection_checkbox (msg);

            /* Info messages (system notifications) get centered styling */
            if (msg.is_info) {
                build_info_row (msg);
                return;
            }

            switch (style) {
            case MessageStyle.IRC:
                build_irc_row (msg, trailing_images, false);
                break;
            case MessageStyle.WORKSPACE:
                build_workspace_row (msg, prev);
                break;
            default:
                build_bubble_row (msg, avatar_display, avatar_scope_enabled,
                                  show_sender_name);
                break;
            }
        }

        /**
         * Forwarded marker, quote block, attachment and body text — the
         * shared middle of every message style. The forwarded indicator
         * replaces the plain sender line in bubbles: it already names the
         * forwarder (incoming) or just reads "Forwarded".
         */
        private void append_content (Gtk.Box box, Message msg,
                                     int quote_width, int quote_lines,
                                     bool irc,
                                     GLib.GenericArray<Message>? trailing,
                                     int text_width) {
            if (msg.is_forwarded) {
                box.append (build_forwarded_indicator (msg));
            }
            if (msg.quote_text != null && msg.quote_text.length > 0) {
                box.append (build_quote_block (msg, quote_width, quote_lines));
            }
            append_attachment (box, msg, irc, trailing);
            if (msg.text != null && msg.text.length > 0) {
                box.append (build_text_widget (msg, text_width));
            }
        }

        /** Edited marker, delivery tick and pin icon, laid inline at the end
            of a compact (IRC / Workspace) row. Bubbles keep them in their own
            footer under the text instead. Workspace bottom-aligns them so the
            hover action bar (top-right) does not cover them. */
        private void append_meta_indicators (Gtk.Box box, Message msg,
                                             Gtk.Align align = Gtk.Align.START) {
            if (msg.is_edited) {
                var edited = build_edited_indicator ("(edited)");
                edited.valign = align;
                box.append (edited);
            }
            if (msg.is_outgoing) {
                var tick = build_tick_indicator (msg);
                if (tick != null) {
                    tick.valign = align;
                    box.append (tick);
                }
            }
            var pin = build_pin_indicator (msg);
            pin.valign = align;
            box.append (pin);
        }

        private void build_bubble_row (Message msg,
                                       BubbleAvatarDisplay avatar_display,
                                       bool avatar_scope_enabled,
                                       bool show_sender_name) {
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

            /* Sticker-only messages drop the bubble chrome so the sticker
               stands on its own; a caption or quote keeps the bubble. */
            if (msg.is_image_only && msg.has_local_file
                && msg.is_sticker_file ()
                && (msg.quote_text == null || msg.quote_text.length == 0)) {
                bubble.add_css_class ("sticker");
            }

            if (!msg.is_forwarded && !outgoing && show_sender_name) {
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

            append_content (bubble, msg, 40, 2, false, null, 50);

            /* Timestamp + delivery/read tick + pin indicator */
            var footer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            footer.halign = Gtk.Align.END;
            if (msg.is_edited) {
                footer.append (build_edited_indicator ("Edited"));
            }
            var time_lbl = new Gtk.Label (format_timestamp (msg.timestamp));
            time_lbl.add_css_class ("message-time");
            footer.append (time_lbl);

            if (outgoing) {
                var tick = build_tick_indicator (msg);
                if (tick != null) footer.append (tick);
            }
            footer.append (build_pin_indicator (msg));
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

        private void build_irc_row (Message msg,
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
            /* Keep the full IRC nick visible.  An ellipsized label has a
               tiny minimum width, so a long message can otherwise squeeze
               the nick down to an ellipsis. */
            sender_lbl.ellipsize = Pango.EllipsizeMode.NONE;
            this.append (sender_lbl);

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
            body.hexpand = true;
            append_content (body, msg, 60, 1, true, trailing_images, -1);
            var reactions_box = build_reactions_box (msg);
            if (reactions_box != null) {
                body.append (reactions_box);
            }
            this.append (body);

            append_meta_indicators (this, msg);
        }

        /* Workspace style: avatar on the left, bold sender name with a small
           timestamp on top, the message below. Consecutive messages from the
           same sender within five minutes drop the avatar and header. */
        private void build_workspace_row (Message msg, Message? prev) {
            this.add_css_class ("message-workspace");
            this.margin_start = 4;
            this.margin_end = 4;

            bool grouped = prev != null && same_sender (prev, msg)
                && msg.timestamp - prev.timestamp < 300
                && same_day (msg.timestamp, prev.timestamp);

            string sender = effective_sender_name (msg);
            var content = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            if (grouped) {
                var gutter = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                gutter.width_request = 36;
                content.append (gutter);
            } else {
                var avatar = presence_avatar (36, sender,
                    msg.is_outgoing ? self_avatar_path : msg.sender_avatar_path,
                    false, "message-avatar");
                avatar.valign = Gtk.Align.START;
                avatar.tooltip_text = msg.sender_address ?? sender;
                content.append (avatar);
            }

            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 1);
            body.hexpand = true;
            if (!grouped) {
                var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
                var sender_lbl = new Gtk.Label (sender);
                sender_lbl.add_css_class ("message-sender");
                sender_lbl.xalign = 0;
                sender_lbl.ellipsize = Pango.EllipsizeMode.END;
                header.append (sender_lbl);
                var time_lbl = new Gtk.Label (format_timestamp (msg.timestamp));
                time_lbl.add_css_class ("message-time");
                time_lbl.valign = Gtk.Align.END;
                header.append (time_lbl);
                body.append (header);
            }
            append_content (body, msg, 60, 1, false, null, -1);
            var reactions_box = build_reactions_box (msg);
            if (reactions_box != null) {
                body.append (reactions_box);
            }
            content.append (body);
            append_meta_indicators (content, msg, Gtk.Align.END);

            /* The hover action bar floats over the top-right corner: it only
               occupies space in the overlay, never in the row layout. Real
               `visible` toggling (not CSS opacity) gates it, so touch taps
               and keyboard focus can never reach hidden buttons. */
            var bar = build_hover_actions ();
            bar.visible = false;
            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect (() => { bar.visible = true; });
            motion.leave.connect (() => { bar.visible = false; });
            this.add_controller (motion);

            var overlay = new Gtk.Overlay ();
            overlay.hexpand = true;
            overlay.child = content;
            overlay.add_overlay (bar);
            this.append (overlay);
        }

        /** Quick-action buttons shown while the pointer is over a Workspace
            row. */
        private Gtk.Widget build_hover_actions () {
            var bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            bar.add_css_class ("message-actions-bar");
            bar.halign = Gtk.Align.END;
            bar.valign = Gtk.Align.START;
            string[,] actions = {
                { "react", "face-smile-symbolic", "React" },
                { "reply", "mail-reply-sender-symbolic", "Reply" },
                { "forward", "mail-forward-symbolic", "Forward" },
                { "pin", "view-pin-symbolic", "Pin / Unpin" },
                { "more", "view-more-symbolic", "More actions" }
            };
            for (int i = 0; i < actions.length[0]; i++) {
                string action = actions[i, 0];
                var btn = new Gtk.Button.from_icon_name (actions[i, 1]);
                btn.add_css_class ("flat");
                btn.tooltip_text = actions[i, 2];
                btn.clicked.connect (() => { action_requested (action, btn); });
                bar.append (btn);
            }
            return bar;
        }

        private void append_selection_checkbox (Message msg) {
            var check = new Gtk.CheckButton ();
            check.add_css_class ("message-select-check");
            check.valign = Gtk.Align.CENTER;
            check.margin_end = 6;
            msg.bind_property ("selection-visible", check, "visible",
                               BindingFlags.SYNC_CREATE);
            msg.bind_property ("selected", check, "active",
                               BindingFlags.SYNC_CREATE);
            check.toggled.connect (() => {
                if (msg.selected != check.active) {
                    msg.selected = check.active;
                }
                selection_toggled (msg.id, check.active);
            });
            this.append (check);
        }

        private void append_attachment (Gtk.Box box, Message msg, bool irc,
                                        GLib.GenericArray<Message>? trailing_images = null) {
            if (!msg.has_file) return;
            if (msg.has_local_file
                && (msg.is_sticker_file () || msg.is_image_file ())) {
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
            var avatar = presence_avatar (20, text,
                msg.is_outgoing ? self_avatar_path : msg.sender_avatar_path,
                false, "message-avatar");
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
            var image = msg.is_sticker_file ()
                ? load_sticker (msg.file_path, msg.is_video_sticker_file ())
                : load_picture (msg.file_path, 400, 400, 260, 0);
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
            var picture = m.is_sticker_file ()
                ? load_sticker (m.file_path, m.is_video_sticker_file ())
                : load_picture (m.file_path, 260, 200, 0, 180);
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

        private const int STICKER_MAX = 200;

        /**
         * Load a GIF/WebP/WebM attachment as a sticker: natural size capped at
         * STICKER_MAX in both dimensions, never upscaled, playing its
         * animation while the "animate stickers" setting is on. WebM uses a
         * muted looping media paintable; raster files with a single frame (or
         * that cannot be decoded as an animation) fall back to a static
         * sticker.
         */
        private static Gtk.Widget? load_sticker (string path,
                                                bool video = false) {
            if (video) return load_video_sticker (path);

            if (animate_stickers) {
                try {
                    var anim = new Gdk.PixbufAnimation.from_file (path);
                    if (!anim.is_static_image ()) {
                        int dw = anim.get_width ();
                        int dh = anim.get_height ();
                        if (dw > 0 && dh > 0) {
                            double scale = double.min (1.0, double.min (
                                (double) STICKER_MAX / dw,
                                (double) STICKER_MAX / dh));
                            dw = int.max (1, (int) (dw * scale + 0.5));
                            dh = int.max (1, (int) (dh * scale + 0.5));

                            var picture = new Gtk.Picture ();
                            picture.set_data<StickerAnimation> (
                                "parla-sticker-animation",
                                new StickerAnimation (picture, anim));
                            picture.content_fit = Gtk.ContentFit.CONTAIN;
                            picture.can_shrink = true;
                            picture.halign = Gtk.Align.FILL;
                            picture.valign = Gtk.Align.FILL;

                            var frame = new ScaledPreviewFrame (
                                dw, dh, "message-sticker");
                            frame.child = picture;
                            frame.halign = Gtk.Align.START;
                            frame.valign = Gtk.Align.START;
                            return frame;
                        }
                    }
                } catch (Error e) {
                    stderr.printf ("  -> Sticker load failed: %s\n", e.message);
                }
            }
            return load_picture (path, STICKER_MAX, STICKER_MAX, 0, 0,
                                 "message-sticker");
        }

        private static Gtk.Widget load_video_sticker (string path) {
            var picture = new Gtk.Picture ();
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            picture.can_shrink = true;
            picture.halign = Gtk.Align.FILL;
            picture.valign = Gtk.Align.FILL;

            var frame = new ScaledPreviewFrame (
                STICKER_MAX, STICKER_MAX, "message-sticker");
            frame.child = picture;
            frame.halign = Gtk.Align.START;
            frame.valign = Gtk.Align.START;

            picture.set_data<StickerVideoAnimation> (
                "parla-sticker-video-animation",
                new StickerVideoAnimation (
                    picture, frame, path, animate_stickers, STICKER_MAX));
            return frame;
        }

        /**
         * Load a file into a Gtk.Picture sized to fit within (max_w, max_h)
         * preserving aspect, then optionally upscaled to (min_w, min_h).
         * Returns null on read failure (and logs to stderr).
         */
        private static Gtk.Widget? load_picture (string path,
                                                  int max_w, int max_h,
                                                  int min_w, int min_h,
                                                  string css_class
                                                      = "message-image") {
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

                var frame = new ScaledPreviewFrame (dw, dh, css_class);
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

        public static bool same_sender (Message a, Message b) {
            if (a.is_info || b.is_info) return false;
            if (a.is_outgoing != b.is_outgoing) return false;
            if (a.is_outgoing) return true;
            if (a.sender_contact_id != b.sender_contact_id) return false;
            /* Same contact can still relay distinct authors (mailing lists,
               bots) via the override name — never merge across those. */
            return (a.override_sender_name ?? "") == (b.override_sender_name ?? "")
                && (a.sender_name ?? "") == (b.sender_name ?? "");
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

        private static Gtk.Label build_pin_indicator (Message msg) {
            var pin = new Gtk.Label ("📌");
            pin.add_css_class ("message-pin");
            pin.tooltip_text = "Pinned";
            msg.bind_property ("is-pinned", pin, "visible",
                               BindingFlags.SYNC_CREATE);
            return pin;
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
            if (Markdown.mode == MarkdownMode.ENABLED) {
                var md_body = build_text_with_markdown_blocks (msg, max_width_chars);
                body = md_body ?? build_markup_label (msg.text, max_width_chars,
                    emoji_only_count (msg.text), mention_roster);
            } else {
                body = build_markup_label (msg.text, max_width_chars,
                    emoji_only_count (msg.text), mention_roster);
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
                                                     int emoji_count = 0,
                                                     MentionRoster? roster = null) {
            var text = new Gtk.Label (raw);
            try {
                string markup = roster != null
                    ? Mentions.render_markup (raw, roster)
                    : Markdown.format (raw);
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
            if (emoji_count == 1) text.add_css_class ("message-big-emoji");
            else if (emoji_count == 2) text.add_css_class ("message-medium-emoji");
            if (max_width_chars > 0) text.max_width_chars = max_width_chars;
            connect_label_links (text);
            return text;
        }

        private static void connect_label_links (Gtk.Label text) {
            /* Delta Chat invite links join in-app instead of bouncing through a
               browser; everything else falls through to the default handler. */
            text.activate_link.connect ((uri) => {
                if (uri.has_prefix ("parla-mention:") && text.get_root () is Dc.Window) {
                    ((Dc.Window) text.get_root ()).open_mention (uri);
                    return true;
                }
                if (is_delta_invite_uri (uri) && text.get_root () is Dc.Window) {
                    ((Dc.Window) text.get_root ()).handle_invite_uri (uri);
                    return true;
                }
                return false;
            });
        }

        private Gtk.Widget? build_text_with_markdown_blocks (Message msg,
                                                             int max_width_chars) {
            string raw = msg.text ?? "";
            var lines = raw.split ("\n");
            var body = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            body.halign = Gtk.Align.FILL;
            body.hexpand = true;

            bool found_block = false;
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
                if (table != null) {
                    append_text_block (body, lines, text_start, i, max_width_chars);
                    body.append (build_table_grid (table, max_width_chars));
                    found_block = true;
                    i = end;
                    text_start = i;
                    continue;
                }

                bool checked;
                int marker_start;
                int content_start;
                if (Markdown.parse_task_checkbox (lines[i], out checked,
                                                  out marker_start,
                                                  out content_start)) {
                    append_text_block (body, lines, text_start, i,
                                       max_width_chars);
                    body.append (build_task_line (msg, i, checked,
                                                  content_start,
                                                  max_width_chars));
                    found_block = true;
                    i++;
                    text_start = i;
                    continue;
                }

                i++;
            }

            if (!found_block) return null;
            append_text_block (body, lines, text_start, lines.length,
                               max_width_chars);
            return body;
        }

        private static bool is_code_fence_line (string line) {
            return line.strip ().has_prefix ("```");
        }

        private void append_text_block (Gtk.Box body, string[] lines,
                                        int start, int end,
                                        int max_width_chars) {
            string text = join_lines (lines, start, end).strip ();
            if (text.length == 0) return;
            body.append (build_markup_label (text, max_width_chars, 0,
                                             mention_roster));
        }

        private static string join_lines (string[] lines, int start, int end) {
            var sb = new StringBuilder ();
            for (int i = start; i < end; i++) {
                if (i > start) sb.append_c ('\n');
                sb.append (lines[i]);
            }
            return sb.str;
        }

        private Gtk.Widget build_task_line (Message msg, int line_index,
                                            bool checked, int content_start,
                                            int max_width_chars) {
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            row.add_css_class ("markdown-task-line");
            row.halign = Gtk.Align.FILL;
            row.hexpand = true;

            string glyph = checked ? "✅" : "⬜";
            if (msg.can_edit_text) {
                var toggle = new Gtk.Button.with_label (glyph);
                toggle.add_css_class ("flat");
                toggle.add_css_class ("markdown-task-toggle");
                toggle.valign = Gtk.Align.START;
                toggle.tooltip_text = checked
                    ? "Mark unchecked"
                    : "Mark checked";
                string raw = msg.text ?? "";
                int idx = line_index;
                toggle.clicked.connect (() => {
                    string? new_text = toggled_task_text (raw, idx);
                    if (new_text == null) return;
                    toggle.sensitive = false;
                    checkbox_toggle_requested (msg.id, new_text);
                });
                row.append (toggle);
            } else {
                var mark = new Gtk.Label (glyph);
                mark.add_css_class ("markdown-task-glyph");
                mark.valign = Gtk.Align.START;
                row.append (mark);
            }

            string line = (msg.text ?? "").split ("\n")[line_index];
            string content = content_start < line.length
                ? line.substring (content_start)
                : "";
            int label_width = max_width_chars > 0
                ? int.max (1, max_width_chars - 4)
                : max_width_chars;
            var label = build_markup_label (content, label_width, 0,
                                            mention_roster);
            label.valign = Gtk.Align.START;
            label.hexpand = true;
            row.append (label);
            return row;
        }

        private static string? toggled_task_text (string raw, int line_index) {
            var lines = raw.split ("\n");
            if (line_index < 0 || line_index >= lines.length) return null;

            bool checked;
            int marker_start;
            int content_start;
            if (!Markdown.parse_task_checkbox (lines[line_index], out checked,
                                               out marker_start,
                                               out content_start)) {
                return null;
            }

            string line = lines[line_index];
            string replacement = checked ? "[ ]" : "[x]";
            lines[line_index] = line.substring (0, marker_start) +
                replacement + line.substring (marker_start + 3);
            return join_lines (lines, 0, lines.length);
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

        /** Number of emoji when the message is emoji-only (whitespace allowed
            between them), 0 otherwise. */
        private static int emoji_only_count (string? raw) {
            if (raw == null) return 0;
            string text = raw.strip ();
            if (text.length == 0) return 0;

            int index = 0;
            int count = 0;
            while (index < text.length) {
                if (!consume_emoji_sequence (text, ref index)) return 0;
                count++;
                consume_whitespace (text, ref index);
            }
            return count;
        }

        private static void consume_whitespace (string text, ref int index) {
            while (true) {
                int next = index;
                unichar c;
                if (!text.get_next_char (ref next, out c)) return;
                if (!c.isspace ()) return;
                index = next;
            }
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
        private Gtk.Box? build_reactions_box (Message msg) {
            bool has_details = msg.reaction_details != null
                && msg.reaction_details.length > 0;
            if (!has_details &&
                (msg.reactions == null || msg.reactions.length == 0)) {
                return null;
            }

            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            box.add_css_class ("reaction-bar");
            box.halign = Gtk.Align.START;

            if (has_details) {
                for (int i = 0; i < msg.reaction_details.length; i++) {
                    box.append (build_reaction_badge (msg, msg.reaction_details[i]));
                }
                return box;
            }

            foreach (string part in msg.reactions.split (",")) {
                var kv = part.split (":", 2);
                if (kv.length < 2) continue;
                var reaction = new MessageReaction (kv[0]);
                reaction.count = int.parse (kv[1]);
                box.append (build_reaction_badge (msg, reaction));
            }
            return box;
        }

        private Gtk.Widget build_reaction_badge (Message msg,
                                                 MessageReaction reaction) {
            string count = reaction.count.to_string ();
            var badge = new Gtk.Button.with_label (
                reaction.count == 1 ? reaction.emoji
                                    : "%s %s".printf (reaction.emoji, count));
            badge.add_css_class ("flat");
            badge.add_css_class ("reaction-badge");
            badge.tooltip_text = "Show reactions";

            var popover = build_reaction_popover (badge, msg, reaction);
            badge.clicked.connect (() => {
                popover.popup ();
            });

            uint hide_id = 0;
            var motion = new Gtk.EventControllerMotion ();
            motion.enter.connect ((x, y) => {
                if (hide_id != 0) {
                    Source.remove (hide_id);
                    hide_id = 0;
                }
                popover.popup ();
            });
            motion.leave.connect (() => {
                if (hide_id != 0) Source.remove (hide_id);
                hide_id = Timeout.add (180, () => {
                    popover.popdown ();
                    hide_id = 0;
                    return Source.REMOVE;
                });
            });
            badge.add_controller (motion);

            return badge;
        }

        private Gtk.Popover build_reaction_popover (Gtk.Widget parent,
                                                    Message msg,
                                                    MessageReaction reaction) {
            var popover = new Gtk.Popover ();
            popover.has_arrow = false;
            popover.autohide = true;
            popover.position = Gtk.PositionType.TOP;
            popover.set_parent (parent);

            var pill = new Gtk.Box (Gtk.Orientation.VERTICAL, 4);
            pill.add_css_class ("reaction-users-pill");

            if (reaction.users.length == 0) {
                var label = new Gtk.Label (reaction.count == 1
                    ? "Unknown user"
                    : "%d reactions".printf (reaction.count));
                label.add_css_class ("reaction-user-name");
                pill.append (label);
            } else {
                for (int i = 0; i < reaction.users.length; i++) {
                    pill.append (build_reaction_user_row (
                        msg, reaction.users[i].contact_id));
                }
            }

            popover.child = pill;
            return popover;
        }

        private Gtk.Widget build_reaction_user_row (Message msg,
                                                    int contact_id) {
            string name;
            string? avatar_path;
            reaction_user_identity (msg, contact_id, out name, out avatar_path);

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            row.add_css_class ("reaction-user-row");
            row.append (presence_avatar (22, name, avatar_path, false));

            var label = new Gtk.Label (name);
            label.add_css_class ("reaction-user-name");
            label.ellipsize = Pango.EllipsizeMode.END;
            label.max_width_chars = 26;
            label.xalign = 0;
            row.append (label);
            return row;
        }

        private void reaction_user_identity (Message msg, int contact_id,
                                             out string name,
                                             out string? avatar_path) {
            avatar_path = null;

            if (contact_id == 1) {
                name = self_display_name != null && self_display_name.length > 0
                    ? self_display_name : "You";
                avatar_path = self_avatar_path;
                return;
            }

            MentionMember? member = reaction_roster != null
                ? reaction_roster.lookup_contact (contact_id) : null;
            if (member != null) {
                name = member.display_name.length > 0
                    ? member.display_name
                    : (member.address.length > 0
                        ? member.address
                        : "Contact %d".printf (contact_id));
                avatar_path = member.avatar_path;
                return;
            }

            if (!msg.is_outgoing && contact_id > 0 &&
                contact_id == msg.sender_contact_id) {
                string? author = effective_author_name (msg);
                name = author ?? msg.sender_address ?? "Contact";
                avatar_path = msg.sender_avatar_path;
                return;
            }

            name = contact_id > 0 ? "Contact %d".printf (contact_id)
                                  : "Unknown user";
        }

        private static string format_timestamp (int64 ts) {
            if (ts <= 0) return "";
            var dt = new DateTime.from_unix_local (ts);
            return dt.format ("%H:%M");
        }

        /** Build a centered date-separator label, styled like info rows. */
        internal static Gtk.Widget build_date_separator (int64 ts) {
            var label = new Gtk.Label (format_date_label (ts));
            label.add_css_class ("dim-label");
            label.add_css_class ("caption");
            label.hexpand = true;
            label.halign = Gtk.Align.CENTER;
            label.justify = Gtk.Justification.CENTER;
            label.margin_top = 8;
            label.margin_bottom = 4;
            return label;
        }

        /** Format a timestamp as a date label: "3 June" (current year) or
            "3 June 2023" (other years). */
        internal static string format_date_label (int64 ts) {
            if (ts <= 0) return "";
            var dt = new DateTime.from_unix_local (ts);
            var now = new DateTime.now_local ();
            int day = dt.get_day_of_month ();
            string month = dt.format ("%B");
            if (dt.get_year () == now.get_year ()) {
                return "%d %s".printf (day, month);
            }
            return "%d %s %d".printf (day, month, dt.get_year ());
        }

        /** True when two unix timestamps fall on the same calendar day. */
        internal static bool same_day (int64 ts1, int64 ts2) {
            if (ts1 <= 0 || ts2 <= 0) return false;
            var dt1 = new DateTime.from_unix_local (ts1);
            var dt2 = new DateTime.from_unix_local (ts2);
            return dt1.get_year () == dt2.get_year () &&
                   dt1.get_day_of_year () == dt2.get_day_of_year ();
        }

    }

}
