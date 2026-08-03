namespace Dc {

    /** Implemented by both gallery cell flavours (grid thumbnails and
        list rows) so GalleryDialog drives them through a single list
        item factory (see GalleryDialog.make_cell_factory). */
    private interface GalleryCell : Gtk.Widget {
        public abstract Message? msg { get; set; }
        public abstract void bind (Message m);
        public abstract void unbind ();
    }

    /**
     * Per-chat media overview mirroring the official Delta Chat gallery:
     * tabs for Apps, Images, Video, Audio and Files. Message ids come from
     * the get_chat_media JSON-RPC call — a metadata-only database query,
     * so nothing is downloaded to build the lists. Core returns the ids
     * oldest first; we display newest first like the official client.
     *
     * Images and videos open in the same fullscreen viewers used by the
     * conversation (ImageViewer / VideoPlayer), overlaid on the dialog.
     */
    public class GalleryDialog : Adw.Dialog {

        /* Media cells are responsive squares: at least CELL_MIN wide (the
           floor decides how many columns fit — three per row on
           phone-width windows, bottoming out at min_columns on anything
           narrower), growing to fill the row so no dead space is left.
           CELL_MAX only bounds the frame's natural size, far above any
           real column. */
        private const int CELL_MIN = 104;
        private const int CELL_MAX = 512;
        private const int FETCH_CHUNK = 50;

        /* The Images and Stickers tabs share viewtypes: anything Parla
           renders as a sticker (webp/gif/webm or Sticker viewtype, see
           Message.is_sticker_file) lands under Stickers, the rest under
           Images. Filtering happens client-side because get_chat_media
           can only match on viewtypes. */
        private enum MediaFilter { ALL, STICKERS_ONLY, NO_STICKERS }

        private unowned Window app_window;
        private unowned RpcClient rpc;
        private int chat_id;

        /* Dialog this gallery was presented on top of (Chat Info). "View
           in Conversation" must close the whole stack, not just the
           gallery, or the leftover dialog re-scrolls the chat when the
           user closes it later. */
        public unowned Adw.Dialog? presenter_dialog = null;

        private Adw.ViewStack view_stack;
        private Adw.ToastOverlay toasts;
        private Gtk.Button save_all_btn;
        private Gtk.MenuButton more_btn;
        private Gtk.Label more_label;
        private Gtk.Image more_icon;
        private SimpleAction section_action;
        private ImageViewer viewer;
        private VideoPlayer player;

        private Gtk.ActionBar selection_bar;
        private Gtk.Label selection_label;
        private Gtk.Button forward_sel_btn;
        private Gtk.Button save_sel_btn;
        private Gtk.Button delete_sel_btn;

        /* Multi-selection mode, entered via "Select…" in an item's context
           menu. Cells watch selection_changed to refresh their checkmarks
           (they are recycled, so they cannot bind once). */
        public bool selection_mode { get; private set; default = false; }
        public signal void selection_changed ();
        private HashTable<int, bool> selected_ids =
            new HashTable<int, bool> (direct_hash, direct_equal);

        private GalleryTab[] tabs = {};
        private bool is_open = true;

        private HashTable<string, Gdk.Texture> thumb_cache =
            new HashTable<string, Gdk.Texture> (str_hash, str_equal);
        private ThreadPool<ThumbRequest>? thumb_pool = null;

        private class GalleryTab : Object {
            public string key;
            public string title;
            public string icon_name;
            /* Up to three core viewtypes queried via get_chat_media. */
            public string[] types;
            public MediaFilter filter;
            public string empty_title;
            public string empty_description;
            /* "…" is substituted with the item kind in save-all texts. */
            public string kind_plural;
            /* Overflow tabs hide from the switcher bar and live in the
               "More" menu instead (at most four regular tabs fit a
               phone-width bottom bar). */
            public bool overflow;
            public GLib.ListStore store = new GLib.ListStore (typeof (Message));
            public Gtk.Stack stack;
            public bool load_started = false;
        }

        private class ThumbRequest {
            public string path;
            public int size;
            public SourceFunc cb;
            public Gdk.Texture? result = null;
        }

        public GalleryDialog (Window window, RpcClient rpc, int chat_id,
                              string? chat_name) {
            this.app_window = window;
            this.rpc = rpc;
            this.chat_id = chat_id;

            title = "Apps and Media";
            content_width = 860;
            content_height = 600;
            /* The compact tab bar (four tabs plus "More") keeps the
               content minimum small; request a sane floor so the dialog
               still lays out sensibly on phone-sized screens. */
            width_request = 320;
            height_request = 400;

            try {
                thumb_pool = new ThreadPool<ThumbRequest>.with_owned_data ((req) => {
                    try {
                        req.result = texture_from_pixbuf (
                            scaled_frame_from_file (req.path, req.size));
                    } catch (Error e) {
                        /* Broken image: the placeholder icon remains. */
                    }
                    Idle.add ((owned) req.cb);
                }, 2, false);
            } catch (Error e) {
                warning ("gallery thumb pool: %s", e.message);
            }

            tabs = {
                new GalleryTab () {
                    key = "images", title = "Images",
                    icon_name = "image-x-generic-symbolic",
                    types = { "Gif", "Image" },
                    filter = MediaFilter.NO_STICKERS,
                    empty_title = "No Images",
                    empty_description = "Images shared in this chat will appear here",
                    kind_plural = "images"
                },
                new GalleryTab () {
                    key = "stickers", title = "Stickers",
                    icon_name = "sticker-symbolic",
                    types = { "Sticker", "Gif", "Image" },
                    filter = MediaFilter.STICKERS_ONLY,
                    empty_title = "No Stickers",
                    empty_description = "Stickers shared in this chat will appear here",
                    kind_plural = "stickers",
                    overflow = true
                },
                new GalleryTab () {
                    key = "video", title = "Video",
                    icon_name = "video-x-generic-symbolic",
                    types = { "Video" },
                    empty_title = "No Videos",
                    empty_description = "Videos shared in this chat will appear here",
                    kind_plural = "videos"
                },
                new GalleryTab () {
                    key = "audio", title = "Audio",
                    icon_name = "audio-x-generic-symbolic",
                    types = { "Audio", "Voice" },
                    empty_title = "No Audio",
                    empty_description = "Audio files and voice messages will appear here",
                    kind_plural = "audio files"
                },
                new GalleryTab () {
                    key = "files", title = "Files",
                    icon_name = "text-x-generic-symbolic",
                    types = { "File" },
                    empty_title = "No Files",
                    empty_description = "Documents and other files shared in this chat will appear here",
                    kind_plural = "files"
                },
                new GalleryTab () {
                    key = "apps", title = "Apps",
                    icon_name = "application-x-executable-symbolic",
                    types = { "Webxdc" },
                    empty_title = "No Apps",
                    empty_description = "Delta Chat apps shared in this chat will appear here",
                    kind_plural = "apps",
                    overflow = true
                },
            };

            view_stack = new Adw.ViewStack ();
            foreach (var tab in tabs) {
                build_tab_page (tab);
                var page = view_stack.add_titled (tab.stack, tab.key,
                                                  tab.title);
                page.icon_name = tab.icon_name;
                tab.store.items_changed.connect (() => {
                    update_tab_badge (tab);
                    if (view_stack.visible_child_name == tab.key)
                        update_save_all_button ();
                });
            }

            var header = new Adw.HeaderBar ();
            header.title_widget = new Adw.WindowTitle ("Apps and Media",
                chat_name ?? "");

            save_all_btn = new Gtk.Button.from_icon_name ("document-save-symbolic");
            save_all_btn.sensitive = false;
            save_all_btn.clicked.connect (() => { on_save_all_clicked (); });
            header.pack_start (save_all_btn);

            /* The tabs always live in a compact bottom bar. Six of them
               do not fit phone-width windows and GNOME has no scrollable
               tab idiom, so only the main sections get switcher tabs; the
               overflow ones hide from the switcher and live in a "More"
               menu button dressed up as a fifth tab. */
            var switcher = new Adw.ViewSwitcher ();
            switcher.stack = view_stack;
            switcher.policy = Adw.ViewSwitcherPolicy.NARROW;

            var more_menu = new GLib.Menu ();
            foreach (var tab in tabs) {
                if (!tab.overflow) continue;
                view_stack.get_page (tab.stack).visible = false;
                more_menu.append (tab.title,
                                  "gallery.section('%s')".printf (tab.key));
            }

            /* Stateful so the active overflow section gets a checkmark in
               the menu; the state is synced from the stack, not here. */
            section_action = new SimpleAction.stateful ("section",
                GLib.VariantType.STRING, new Variant.string ("images"));
            section_action.activate.connect ((param) => {
                view_stack.visible_child_name = param.get_string ();
            });
            var gallery_actions = new SimpleActionGroup ();
            gallery_actions.add_action (section_action);
            insert_action_group ("gallery", gallery_actions);

            more_icon = new Gtk.Image.from_icon_name ("view-more-symbolic");
            more_label = new Gtk.Label ("More");
            more_label.add_css_class ("caption");
            var more_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            more_box.valign = Gtk.Align.CENTER;
            more_box.append (more_icon);
            more_box.append (more_label);

            more_btn = new Gtk.MenuButton ();
            more_btn.child = more_box;
            more_btn.menu_model = more_menu;
            more_btn.direction = Gtk.ArrowType.UP;
            more_btn.add_css_class ("flat");
            more_btn.add_css_class ("gallery-more");

            var switcher_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            switcher_bar.halign = Gtk.Align.CENTER;
            /* Strips the buttons' spare padding and minimum width (see
               application.vala) so the whole bar fits narrow windows. */
            switcher_bar.add_css_class ("gallery-tabs");
            switcher_bar.append (switcher);
            switcher_bar.append (more_btn);

            selection_bar = new Gtk.ActionBar ();
            selection_bar.revealed = false;

            var cancel_selection = new Gtk.Button.with_label ("Cancel");
            cancel_selection.clicked.connect (() => { exit_selection_mode (); });
            selection_bar.pack_start (cancel_selection);

            selection_label = new Gtk.Label ("");
            selection_bar.set_center_widget (selection_label);

            forward_sel_btn = new Gtk.Button.with_label ("Forward…");
            forward_sel_btn.add_css_class ("suggested-action");
            forward_sel_btn.clicked.connect (() => { forward_selection (); });
            selection_bar.pack_end (forward_sel_btn);

            save_sel_btn = new Gtk.Button.with_label ("Save…");
            save_sel_btn.clicked.connect (() => { save_selection (); });
            selection_bar.pack_end (save_sel_btn);

            delete_sel_btn = new Gtk.Button.with_label ("Delete…");
            delete_sel_btn.add_css_class ("destructive-action");
            delete_sel_btn.clicked.connect (() => { delete_selection (); });
            selection_bar.pack_end (delete_sel_btn);

            var toolbar_view = new Adw.ToolbarView ();
            toolbar_view.add_top_bar (header);
            toolbar_view.add_bottom_bar (switcher_bar);
            toolbar_view.add_bottom_bar (selection_bar);
            toolbar_view.content = view_stack;

            /* Same fullscreen viewers the conversation uses, overlaid on the
               dialog (the window-level ones would be hidden behind it). */
            viewer = new ImageViewer ();
            viewer.set_window (window);
            player = new VideoPlayer ();
            player.set_window (window);

            var media_overlay = new Gtk.Overlay ();
            media_overlay.child = toolbar_view;
            media_overlay.add_overlay (viewer.widget);
            media_overlay.add_overlay (player.widget);

            /* The overlay being the dialog's direct child also makes
               Window.show_toast route toasts here while we are modal. */
            toasts = new Adw.ToastOverlay ();
            toasts.child = media_overlay;
            child = toasts;

            /* Route keys to the fullscreen viewers while they are open, so
               arrows navigate and Escape closes the viewer, not the dialog. */
            var kc = new Gtk.EventControllerKey ();
            kc.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            kc.key_pressed.connect ((kv, code, state) => {
                if (viewer.visible) return viewer.handle_key (kv);
                if (player.visible) return player.handle_key (kv);
                return false;
            });
            ((Gtk.Widget) this).add_controller (kc);

            /* The dialog's own Escape shortcut fires at the window root,
               before the controller above — block it while a viewer is up
               (can_close) and dismiss the viewer from close_attempt. */
            viewer.widget.notify["visible"].connect (() => {
                update_can_close ();
            });
            player.widget.notify["visible"].connect (() => {
                update_can_close ();
            });
            close_attempt.connect (() => {
                if (viewer.visible) {
                    viewer.hide ();
                } else if (player.visible) {
                    player.hide ();
                } else if (selection_mode) {
                    exit_selection_mode ();
                } else {
                    force_close ();
                }
            });

            closed.connect (() => {
                is_open = false;
                var playback = AudioPlayback.shared ();
                if (playback_was_started &&
                    playback.current_message_id > 0) {
                    playback.stop ();
                }
            });

            view_stack.notify["visible-child-name"].connect (() => {
                var tab = current_tab ();
                if (tab != null) load_tab.begin (tab);
                update_save_all_button ();
                sync_more_button ();
            });

            /* Images is the most useful default in Parla (unlike the
               official client, Parla cannot run Webxdc apps yet). */
            view_stack.visible_child_name = "images";
            update_save_all_button ();
            sync_more_button ();
            load_tab.begin (find_tab ("images"));
        }

        /* While an overflow section is open none of the regular switcher
           tabs is active, so the "More" button borrows that section's
           icon and title plus the switcher's selected look. */
        private void sync_more_button () {
            var key = view_stack.visible_child_name ?? "";
            section_action.set_state (new Variant.string (key));
            var tab = find_tab (key);
            if (tab != null && tab.overflow) {
                more_icon.icon_name = tab.icon_name;
                more_label.label = tab.title;
                more_btn.add_css_class ("gallery-more-active");
            } else {
                more_icon.icon_name = "view-more-symbolic";
                more_label.label = "More";
                more_btn.remove_css_class ("gallery-more-active");
            }
        }

        private bool playback_was_started = false;

        /* Escape first dismisses a fullscreen viewer, then leaves selection
           mode, and only then closes the dialog. */
        private void update_can_close () {
            can_close = !viewer.visible && !player.visible && !selection_mode;
        }

        /* ================================================================
         *  Multi-selection
         * ================================================================ */

        public bool is_selected (int msg_id) {
            return selected_ids.contains (msg_id);
        }

        private void enter_selection_mode (int msg_id) {
            selection_mode = true;
            selected_ids.replace (msg_id, true);
            update_selection_ui ();
        }

        private void exit_selection_mode () {
            if (!selection_mode) return;
            selection_mode = false;
            selected_ids.remove_all ();
            update_selection_ui ();
        }

        private void toggle_selected (Message m) {
            if (selected_ids.contains (m.id)) selected_ids.remove (m.id);
            else selected_ids.replace (m.id, true);
            update_selection_ui ();
        }

        private void update_selection_ui () {
            uint count = selected_ids.size ();
            selection_bar.revealed = selection_mode;
            selection_label.label = "%u selected".printf (count);
            forward_sel_btn.sensitive = count > 0;
            save_sel_btn.sensitive = count > 0;
            delete_sel_btn.sensitive = count > 0;
            update_can_close ();
            selection_changed ();
        }

        /** Selected messages in per-tab store order (newest first), so bulk
            actions keep a stable, predictable ordering. */
        private Message[] selected_messages () {
            Message[] result = {};
            foreach (var tab in tabs) {
                for (uint i = 0; i < tab.store.get_n_items (); i++) {
                    var m = (Message) tab.store.get_item (i);
                    if (m != null && selected_ids.contains (m.id)) result += m;
                }
            }
            return result;
        }

        private void forward_selection () {
            var msgs = selected_messages ();
            if (msgs.length == 0) return;
            int[] ids = {};
            foreach (var m in msgs) ids += m.id;
            /* Leave selection mode only once a destination is picked, so
               cancelling the picker keeps the selection intact. */
            MessageActions.forward_with_picker (app_window, rpc, ids,
                () => { exit_selection_mode (); });
        }

        private void save_selection () {
            /* Leave selection mode only once a folder is picked, so
               cancelling the chooser keeps the selection intact. */
            choose_folder_then_save (selected_messages (),
                () => { exit_selection_mode (); });
        }

        private void delete_selection () {
            var msgs = selected_messages ();
            if (msgs.length == 0) return;
            int[] ids = {};
            bool all_outgoing = true;
            foreach (var m in msgs) {
                ids += m.id;
                if (!m.is_outgoing) all_outgoing = false;
            }
            confirm_delete_ids (ids, all_outgoing);
        }

        /** Confirmation shared by the selection bar and the item context
            menu. Only fully-outgoing selections offer Delete for Everyone. */
        private void confirm_delete_ids (owned int[] ids, bool all_outgoing) {
            string title = ids.length == 1
                ? "Delete Message?" : "Delete Messages?";
            string what = ids.length == 1
                ? "this message" : "these %d messages".printf (ids.length);
            if (all_outgoing) {
                confirm_delete_options (this, title,
                    "Delete %s from your device only, or from all participants? This cannot be undone.".printf (what),
                    () => { delete_messages_ui.begin (ids, false); },
                    () => { delete_messages_ui.begin (ids, true); });
            } else {
                confirm_delete_options (this, title,
                    "Delete %s from your device? This cannot be undone.".printf (what),
                    () => { delete_messages_ui.begin (ids, false); },
                    null);
            }
        }

        /* ================================================================
         *  Tab pages
         * ================================================================ */

        private void build_tab_page (GalleryTab tab) {
            tab.stack = new Gtk.Stack ();
            tab.stack.transition_type = Gtk.StackTransitionType.CROSSFADE;

            var spinner = new Gtk.Spinner ();
            spinner.spinning = true;
            spinner.width_request = 32;
            spinner.height_request = 32;
            spinner.halign = Gtk.Align.CENTER;
            spinner.valign = Gtk.Align.CENTER;
            tab.stack.add_named (spinner, "loading");

            var empty = new Adw.StatusPage ();
            empty.icon_name = tab.icon_name;
            empty.title = tab.empty_title;
            empty.description = tab.empty_description;
            empty.add_css_class ("compact");
            tab.stack.add_named (empty, "empty");

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.hexpand = true;
            scroll.vexpand = true;
            if (tab.key == "images" || tab.key == "stickers"
                || tab.key == "video") {
                scroll.child = build_media_grid (tab);
            } else {
                scroll.child = build_row_list (tab);
            }
            tab.stack.add_named (scroll, "content");

            tab.stack.visible_child_name = "loading";
        }

        private GalleryTab? find_tab (string key) {
            foreach (var tab in tabs) {
                if (tab.key == key) return tab;
            }
            return null;
        }

        private GalleryTab? current_tab () {
            var key = view_stack.visible_child_name;
            return key != null ? find_tab (key) : null;
        }

        private void update_tab_badge (GalleryTab tab) {
            view_stack.get_page (tab.stack).badge_number =
                tab.store.get_n_items ();
        }

        /* ================================================================
         *  Loading
         * ================================================================ */

        private async void load_tab (GalleryTab? tab) {
            if (tab == null || tab.load_started) return;
            tab.load_started = true;
            try {
                int[] ids = yield rpc.get_chat_media (chat_id, tab.types);
                if (!is_open) return;

                /* Newest first, like the official client. */
                for (int i = 0, j = ids.length - 1; i < j; i++, j--) {
                    int t = ids[i]; ids[i] = ids[j]; ids[j] = t;
                }

                for (int off = 0; off < ids.length; off += FETCH_CHUNK) {
                    int len = int.min (FETCH_CHUNK, ids.length - off);
                    var msgs = yield rpc.get_parsed_messages (
                        ids[off : off + len]);
                    if (!is_open) return;
                    append_messages (tab, msgs);
                    if (tab.store.get_n_items () > 0)
                        tab.stack.visible_child_name = "content";
                }
            } catch (Error e) {
                if (!is_open) return;
                toast ("Could not load media: " + e.message);
            }
            if (tab.store.get_n_items () == 0)
                tab.stack.visible_child_name = "empty";
        }

        private void append_messages (GalleryTab tab, Message[] msgs) {
            Object[] batch = {};
            foreach (var msg in msgs) {
                if (!msg.has_file) continue;
                if (tab.filter == MediaFilter.STICKERS_ONLY
                    && !msg.is_sticker_file ()) continue;
                if (tab.filter == MediaFilter.NO_STICKERS
                    && msg.is_sticker_file ()) continue;
                batch += msg;
            }
            /* One splice per chunk avoids a per-row relayout storm. */
            if (batch.length > 0)
                tab.store.splice (tab.store.get_n_items (), 0, batch);
        }

        /* ================================================================
         *  Image / video grid
         * ================================================================ */

        private delegate Gtk.Widget CellCreator ();

        private static Gtk.SignalListItemFactory make_cell_factory (
                owned CellCreator create) {
            var factory = new Gtk.SignalListItemFactory ();
            factory.setup.connect ((obj) => {
                ((Gtk.ListItem) obj).child = create ();
            });
            factory.bind.connect ((obj) => {
                var item = (Gtk.ListItem) obj;
                ((GalleryCell) item.child).bind ((Message) item.item);
            });
            factory.unbind.connect ((obj) => {
                var item = (Gtk.ListItem) obj;
                ((GalleryCell) item.child).unbind ();
            });
            return factory;
        }

        private Gtk.GridView build_media_grid (GalleryTab tab) {
            bool is_video = tab.key == "video";
            /* Stickers are transparent cut-outs: show them whole instead
               of cover-cropping like photos. */
            bool contain = tab.key == "stickers";
            var factory = make_cell_factory (
                () => new MediaCell (this, is_video, contain));

            var grid = new Gtk.GridView (new Gtk.NoSelection (tab.store),
                                         factory);
            grid.single_click_activate = true;
            /* Never a single huge picture per row, even below CELL_MIN's
               two-column break point. */
            grid.min_columns = 2;
            grid.max_columns = 12;
            grid.add_css_class ("gallery-grid");
            grid.activate.connect ((pos) => {
                on_media_activated (tab, pos);
            });
            install_menu_key (grid);
            return grid;
        }

        private class MediaCell : Gtk.Box, GalleryCell {
            public Message? msg { get; set; }

            private unowned GalleryDialog dialog;
            private bool is_video;
            private Gtk.Picture picture;
            private Gtk.Image placeholder;
            private Gtk.Box? play_badge = null;
            private Gtk.CheckButton check;
            private int generation = 0;

            public MediaCell (GalleryDialog dialog, bool is_video,
                              bool contain = false) {
                Object (orientation: Gtk.Orientation.VERTICAL, spacing: 0);
                this.dialog = dialog;
                this.is_video = is_video;

                picture = new Gtk.Picture ();
                picture.content_fit = contain
                    ? Gtk.ContentFit.CONTAIN : Gtk.ContentFit.COVER;
                picture.can_shrink = true;
                picture.halign = Gtk.Align.FILL;
                picture.valign = Gtk.Align.FILL;

                var overlay = new Gtk.Overlay ();
                overlay.child = picture;

                placeholder = new Gtk.Image.from_icon_name (
                    is_video ? "video-x-generic-symbolic"
                             : "image-x-generic-symbolic");
                placeholder.pixel_size = 28;
                placeholder.halign = Gtk.Align.CENTER;
                placeholder.valign = Gtk.Align.CENTER;
                placeholder.add_css_class ("dim-label");
                overlay.add_overlay (placeholder);

                if (is_video) {
                    play_badge = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
                    play_badge.add_css_class ("message-video-play");
                    play_badge.halign = Gtk.Align.CENTER;
                    play_badge.valign = Gtk.Align.CENTER;
                    play_badge.can_target = false;
                    var play = new Gtk.Image.from_icon_name (
                        "media-playback-start-symbolic");
                    play.pixel_size = 18;
                    play_badge.append (play);
                    play_badge.visible = false;
                    overlay.add_overlay (play_badge);
                }

                /* Selection checkmark; the cell click toggles, so the
                   check itself must not swallow the press. */
                check = new Gtk.CheckButton ();
                check.add_css_class ("selection-mode");
                check.can_target = false;
                check.halign = Gtk.Align.END;
                check.valign = Gtk.Align.START;
                check.margin_top = 6;
                check.margin_end = 6;
                check.visible = false;
                overlay.add_overlay (check);

                /* Uniform square cells regardless of image aspect. The
                   frame's CELL_MAX natural size is never reached, so its
                   height-for-width tracks the allocated width 1:1 and the
                   cell stays square while filling whatever column width
                   GridView hands out. The frame's 1px measure minimum
                   must be floored back up, otherwise GridView packs
                   max_columns crushed cells; the floor is deliberately
                   unscaled so phone-width windows keep two columns
                   regardless of the user's font scale. */
                var frame = new ScaledPreviewFrame (CELL_MAX, CELL_MAX,
                                                    "gallery-thumb");
                frame.set_size_request (CELL_MIN, -1);
                if (contain) frame.add_css_class ("gallery-thumb-checker");
                frame.child = overlay;
                append (frame);

                add_context_menu_gestures (this, dialog);
                /* Cells live exactly as long as the dialog, so the
                   handler needs no per-bind bookkeeping. */
                dialog.selection_changed.connect (() => {
                    update_selection_visuals ();
                });
            }

            public void bind (Message m) {
                msg = m;
                generation++;
                picture.paintable = null;
                placeholder.visible = true;
                if (play_badge != null) play_badge.visible = false;
                tooltip_text = m.display_file_name ();
                update_selection_visuals ();

                if (!m.has_local_file) {
                    placeholder.icon_name = "image-missing-symbolic";
                    return;
                }
                placeholder.icon_name = is_video
                    ? "video-x-generic-symbolic" : "image-x-generic-symbolic";

                /* WebM (video stickers included) can't become a pixbuf;
                   a paused MediaFile shows the first frame. Deliberately
                   NOT muted: GtkMediaStream.muted poisons the per-app
                   PipeWire mute that WirePlumber then restores onto voice
                   playback, and a paused stream is silent anyway. */
                if (is_video || m.is_video_sticker_file ()) {
                    var media = Gtk.MediaFile.for_filename (m.file_path);
                    media.pause ();
                    picture.paintable = media;
                    placeholder.visible = false;
                    if (play_badge != null) play_badge.visible = true;
                    return;
                }

                int gen = generation;
                dialog.load_thumb.begin (m.file_path, (o, res) => {
                    var tex = dialog.load_thumb.end (res);
                    if (gen != generation || tex == null) return;
                    picture.paintable = tex;
                    placeholder.visible = false;
                });
            }

            public void unbind () {
                msg = null;
                generation++;
                picture.paintable = null;
            }

            private void update_selection_visuals () {
                check.visible = dialog.selection_mode;
                check.active = msg != null && dialog.is_selected (msg.id);
            }
        }

        private async Gdk.Texture? load_thumb (string path) {
            var cached = thumb_cache.lookup (path);
            if (cached != null) return cached;
            if (thumb_pool == null) return null;

            var req = new ThumbRequest ();
            req.path = path;
            /* 2x for crisp rendering on hidpi displays. */
            req.size = CELL_MIN * 2;
            req.cb = load_thumb.callback;
            try {
                thumb_pool.add (req);
            } catch (Error e) {
                return null;
            }
            yield;
            if (req.result != null) thumb_cache.insert (path, req.result);
            return req.result;
        }

        /** False (with a toast) when the attachment is not downloaded. */
        private bool ensure_local_file (Message m) {
            if (m.has_local_file) return true;
            toast ("File not available");
            return false;
        }

        private void on_media_activated (GalleryTab tab, uint pos) {
            var m = (Message) tab.store.get_item (pos);
            if (m == null) return;
            if (selection_mode) {
                toggle_selected (m);
                return;
            }
            if (!ensure_local_file (m)) return;
            /* WebM stickers cannot become a Gdk.Texture; play them like
               videos instead. */
            if (tab.key == "video" || m.is_video_sticker_file ()) {
                player.show (m.file_path, m.file_name);
                return;
            }
            /* Fullscreen viewer navigating the gallery's own image list,
               mirroring how the conversation view collects its paths. */
            string[] paths = {};
            int start = 0;
            for (uint i = 0; i < tab.store.get_n_items (); i++) {
                var it = (Message) tab.store.get_item (i);
                if (it == null || !it.has_local_file
                    || it.is_video_sticker_file ()) continue;
                if (it.id == m.id) start = paths.length;
                paths += it.file_path;
            }
            viewer.show_list (paths, start);
        }

        /* ================================================================
         *  Apps / audio / files lists
         * ================================================================ */

        private Gtk.ListView build_row_list (GalleryTab tab) {
            var factory = make_cell_factory (
                () => new GalleryRow (this, tab.key));

            var list = new Gtk.ListView (new Gtk.NoSelection (tab.store),
                                         factory);
            list.single_click_activate = true;
            list.add_css_class ("gallery-list");
            list.activate.connect ((pos) => {
                var m = (Message) tab.store.get_item (pos);
                if (m != null) on_row_activated (tab, m);
            });
            install_menu_key (list);
            return list;
        }

        private class GalleryRow : Gtk.Box, GalleryCell {
            public Message? msg { get; set; }

            private unowned GalleryDialog dialog;
            private string tab_key;
            private Gtk.CheckButton check;
            private Gtk.Image icon;
            private Gtk.Label title_label;
            private Gtk.Label subtitle_label;
            private Gtk.Button? play_btn = null;
            /* AudioPlayback outlives the dialog, so unlike the dialog's
               own selection_changed these must disconnect on unbind. */
            private ulong playing_handler = 0;
            private ulong current_handler = 0;

            public GalleryRow (GalleryDialog dialog, string tab_key) {
                Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 12);
                this.dialog = dialog;
                this.tab_key = tab_key;
                add_css_class ("gallery-row");
                margin_start = 12;
                margin_end = 12;
                margin_top = 8;
                margin_bottom = 8;

                /* The row click toggles selection, so the check itself
                   must not swallow the press. */
                check = new Gtk.CheckButton ();
                check.valign = Gtk.Align.CENTER;
                check.can_target = false;
                check.visible = false;
                append (check);

                icon = new Gtk.Image ();
                icon.pixel_size = 24;
                append (icon);

                var text_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                text_box.hexpand = true;
                text_box.valign = Gtk.Align.CENTER;

                title_label = new Gtk.Label ("");
                title_label.xalign = 0;
                title_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
                text_box.append (title_label);

                subtitle_label = new Gtk.Label ("");
                subtitle_label.xalign = 0;
                subtitle_label.ellipsize = Pango.EllipsizeMode.END;
                subtitle_label.add_css_class ("dim-label");
                subtitle_label.add_css_class ("caption");
                text_box.append (subtitle_label);
                append (text_box);

                if (tab_key == "audio") {
                    play_btn = new Gtk.Button.from_icon_name (
                        "media-playback-start-symbolic");
                    play_btn.add_css_class ("circular");
                    play_btn.add_css_class ("flat");
                    play_btn.valign = Gtk.Align.CENTER;
                    play_btn.tooltip_text = "Play";
                    play_btn.clicked.connect (() => {
                        if (msg != null) dialog.toggle_audio (msg);
                    });
                    append (play_btn);
                }

                add_context_menu_gestures (this, dialog);
                dialog.selection_changed.connect (() => {
                    update_selection_visuals ();
                });
            }

            public void bind (Message m) {
                msg = m;
                update_selection_visuals ();

                string sender = m.is_outgoing ? "You"
                    : (m.override_sender_name ?? m.sender_name ?? "");
                string when = format_date_time (m.timestamp);
                string meta = sender.length > 0
                    ? "%s · %s".printf (sender, when) : when;

                switch (tab_key) {
                case "audio":
                    bool voice = m.view_type != null
                        && m.view_type.down () == "voice";
                    icon.icon_name = voice
                        ? "audio-input-microphone-symbolic"
                        : "audio-x-generic-symbolic";
                    title_label.label = voice
                        ? "Voice message" : m.display_file_name ("Audio");
                    subtitle_label.label = meta;
                    var playback = AudioPlayback.shared ();
                    playing_handler = playback.notify["playing"].connect (
                        () => { update_play_icon (); });
                    current_handler = playback.notify["current-message-id"]
                        .connect (() => { update_play_icon (); });
                    update_play_icon ();
                    play_btn.sensitive = m.has_local_file;
                    break;
                case "apps":
                    icon.icon_name = "application-x-executable-symbolic";
                    title_label.label = app_display_name (m);
                    subtitle_label.label = meta;
                    break;
                default:
                    icon.gicon = file_type_icon (m);
                    title_label.label = m.display_file_name ();
                    subtitle_label.label = m.file_bytes > 0
                        ? "%s · %s".printf (
                            GLib.format_size (m.file_bytes), meta)
                        : meta;
                    break;
                }
            }

            public void unbind () {
                var playback = AudioPlayback.shared ();
                if (playing_handler != 0) {
                    playback.disconnect (playing_handler);
                    playing_handler = 0;
                }
                if (current_handler != 0) {
                    playback.disconnect (current_handler);
                    current_handler = 0;
                }
                msg = null;
            }

            private void update_selection_visuals () {
                check.visible = dialog.selection_mode;
                check.active = msg != null && dialog.is_selected (msg.id);
            }

            private void update_play_icon () {
                if (play_btn == null || msg == null) return;
                var playback = AudioPlayback.shared ();
                bool this_playing = playback.current_message_id == msg.id
                    && playback.playing;
                play_btn.icon_name = this_playing
                    ? "media-playback-pause-symbolic"
                    : "media-playback-start-symbolic";
                play_btn.tooltip_text = this_playing ? "Pause" : "Play";
            }

            private static GLib.Icon file_type_icon (Message m) {
                string mime = m.file_mime ?? "";
                if (mime.length == 0 && m.file_name != null) {
                    bool uncertain;
                    mime = GLib.ContentType.guess (m.file_name, null,
                                                   out uncertain);
                }
                if (mime.length > 0) {
                    return GLib.ContentType.get_icon (mime);
                }
                return new GLib.ThemedIcon ("text-x-generic-symbolic");
            }

            private static string app_display_name (Message m) {
                string name = m.display_file_name ("App");
                if (name.down ().has_suffix (".xdc")) {
                    name = name[0 : name.length - 4];
                }
                return name;
            }
        }

        private void on_row_activated (GalleryTab tab, Message m) {
            if (selection_mode) {
                toggle_selected (m);
                return;
            }
            switch (tab.key) {
            case "audio":
                toggle_audio (m);
                break;
            case "files":
                open_file (m);
                break;
            case "apps":
                toast ("Delta Chat apps cannot be started in Parla yet");
                break;
            }
        }

        private void toggle_audio (Message m) {
            if (!ensure_local_file (m)) return;
            var playback = AudioPlayback.shared ();
            if (playback.current_message_id == m.id) {
                playback.toggle ();
            } else {
                playback.play_message (m, rpc.account_id);
                playback_was_started = true;
            }
        }

        private void open_file (Message m) {
            if (!ensure_local_file (m)) return;
            var launcher = new Gtk.FileLauncher (
                File.new_for_path (m.file_path));
            launcher.launch.begin (app_window, null, (o, res) => {
                try {
                    launcher.launch.end (res);
                } catch (Error e) {
                    if (!is_dialog_dismissal (e))
                        toast ("Could not open file: " + e.message);
                }
            });
        }

        /* ================================================================
         *  Context menu
         * ================================================================ */

        /** Right click and touch long-press open the item context menu.
            The message is read at event time because cells are recycled
            and rebound to different messages. */
        private static void add_context_menu_gestures (GalleryCell cell,
                                                       GalleryDialog dialog) {
            var widget = (Gtk.Widget) cell;
            var right_click = new Gtk.GestureClick ();
            right_click.button = 3;
            right_click.pressed.connect ((n, x, y) => {
                if (cell.msg != null)
                    dialog.show_item_menu (widget, cell.msg, x, y);
            });
            widget.add_controller (right_click);

            var long_press = new Gtk.GestureLongPress ();
            long_press.touch_only = true;
            long_press.pressed.connect ((x, y) => {
                if (cell.msg != null)
                    dialog.show_item_menu (widget, cell.msg, x, y);
            });
            widget.add_controller (long_press);
        }

        /** Menu / Shift+F10 on a grid or list opens the context menu for
            the focused cell. The controller sits on the view because the
            focusable widget is GTK's internal list item, not our cell. */
        private void install_menu_key (Gtk.Widget view) {
            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((kv, code, state) => {
                bool menu_key = kv == Gdk.Key.Menu
                    || (kv == Gdk.Key.F10
                        && (state & Gdk.ModifierType.SHIFT_MASK) != 0);
                if (!menu_key) return false;

                var item = view.get_focus_child ();
                var cell = item != null
                    ? item.get_first_child () as GalleryCell : null;
                if (cell == null || cell.msg == null) return false;

                var widget = (Gtk.Widget) cell;
                show_item_menu (widget, cell.msg,
                                widget.get_width () / 2.0,
                                widget.get_height () / 2.0);
                return true;
            });
            view.add_controller (keys);
        }

        private void show_item_menu (Gtk.Widget parent, Message m,
                                     double x, double y) {
            Gtk.Box vbox;
            var popover = popover_menu (parent, x, y, out vbox);

            if (m.has_local_file) {
                string fpath = m.file_path;
                string? fname = m.file_name;
                vbox.append (popover_menu_button (popover, "Save As…", () => {
                    app_window.save_attachment.begin (fpath, fname);
                }));
            }

            int msg_id = m.id;
            vbox.append (popover_menu_button (popover, "Forward…", () => {
                MessageActions.forward_with_picker (app_window, rpc,
                                                    new int[] { msg_id });
            }));

            vbox.append (popover_menu_button (popover, "Select…", () => {
                enter_selection_mode (msg_id);
            }));

            vbox.append (popover_menu_button (popover, "View in Conversation",
                () => {
                    /* Each closing dialog restores the window focus it saved
                       when presented, and such a focus shift can scroll the
                       chat. Close the stack bottom-up through the closed
                       signals and jump only once the last one is gone, so
                       nothing runs after the jump to drag the viewport away. */
                    int target_chat = chat_id;
                    var presenter = presenter_dialog;
                    closed.connect (() => {
                        if (presenter != null) {
                            presenter.closed.connect (() => {
                                app_window.open_conversation_message (
                                    target_chat, msg_id);
                            });
                            presenter.close ();
                        } else {
                            app_window.open_conversation_message (
                                target_chat, msg_id);
                        }
                    });
                    close ();
                }));

            /* Collect sticker attachments into a local pack */
            if (m.is_sticker_file () && m.has_local_file) {
                string spath = m.file_path;
                vbox.append (popover_menu_button (popover, "Add Sticker…", () => {
                    StickerManagerDialog.prompt_add_sticker (app_window, spath);
                }));
            }

            vbox.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));

            bool is_outgoing = m.is_outgoing;
            vbox.append (popover_menu_button (popover, "Delete…", () => {
                confirm_delete_ids ({ msg_id }, is_outgoing);
            }, true));

            popover.popup ();
        }

        private async void delete_messages_ui (owned int[] ids, bool for_all) {
            try {
                if (for_all) {
                    yield rpc.delete_messages_for_all (ids);
                } else {
                    yield rpc.delete_messages (ids);
                }
                var deleted = new HashTable<int, bool> (direct_hash,
                                                        direct_equal);
                foreach (int msg_id in ids) {
                    deleted.replace (msg_id, true);
                    selected_ids.remove (msg_id);
                }
                foreach (var tab in tabs) {
                    for (int i = (int) tab.store.get_n_items () - 1;
                         i >= 0; i--) {
                        var m = (Message) tab.store.get_item (i);
                        if (m != null && deleted.contains (m.id))
                            tab.store.remove (i);
                    }
                    if (tab.load_started && tab.store.get_n_items () == 0)
                        tab.stack.visible_child_name = "empty";
                }
                app_window.request_chat_messages_reload (chat_id);
                toast (ids.length == 1 ? "Message deleted"
                       : "%d messages deleted".printf (ids.length));
            } catch (Error e) {
                toast ("Delete failed: " + e.message);
            }
            if (selection_mode && selected_ids.size () == 0)
                exit_selection_mode ();
            else if (selection_mode)
                update_selection_ui ();
        }

        /* ================================================================
         *  Save all
         * ================================================================ */

        private void update_save_all_button () {
            var tab = current_tab ();
            bool has_items = tab != null && tab.store.get_n_items () > 0;
            save_all_btn.sensitive = has_items;
            save_all_btn.tooltip_text = tab != null
                ? "Save all %s to a folder…".printf (tab.kind_plural)
                : "Save all to a folder…";
        }

        private void on_save_all_clicked () {
            var tab = current_tab ();
            if (tab == null) return;
            Message[] msgs = {};
            for (uint i = 0; i < tab.store.get_n_items (); i++) {
                var m = (Message) tab.store.get_item (i);
                if (m != null) msgs += m;
            }
            choose_folder_then_save (msgs);
        }

        /** Shared by "save all" and the selection bar's "Save…"; items
            without a downloaded file are only counted as skipped.
            on_picked runs only when a folder was actually chosen. */
        private void choose_folder_then_save (owned Message[] msgs,
                                              owned VoidFunc? on_picked = null) {
            Message[] items = {};
            int skipped = 0;
            foreach (var m in msgs) {
                if (m.has_local_file) items += m;
                else skipped++;
            }
            if (items.length == 0) {
                toast ("No downloaded files to save");
                return;
            }
            var chooser = new Gtk.FileDialog ();
            chooser.title = "Select Folder";
            chooser.select_folder.begin (app_window, null, (o, res) => {
                try {
                    var folder = chooser.select_folder.end (res);
                    if (folder == null) return;
                    if (on_picked != null) on_picked ();
                    save_files_to_folder.begin (items, skipped, folder);
                } catch (Error e) {
                    if (!is_dialog_dismissal (e))
                        toast ("Folder selection failed: " + e.message);
                }
            });
        }

        private async void save_files_to_folder (owned Message[] items,
                                                 int skipped, File folder) {
            var progress = new Gtk.ProgressBar ();
            progress.hexpand = true;

            var file_label = new Gtk.Label ("");
            file_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            file_label.add_css_class ("dim-label");
            file_label.add_css_class ("caption");

            var pbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            pbox.append (progress);
            pbox.append (file_label);

            var alert = new Adw.AlertDialog ("Saving Files", null);
            alert.extra_child = pbox;
            alert.add_response ("cancel", "Cancel");
            alert.close_response = "cancel";

            var cancellable = new Cancellable ();
            bool finished = false;
            alert.response.connect ((r) => {
                if (!finished) cancellable.cancel ();
            });
            alert.present (this);

            int saved = 0;
            int failed = 0;
            for (int i = 0; i < items.length; i++) {
                if (cancellable.is_cancelled ()) break;
                var m = items[i];
                string name = m.display_file_name (
                    Path.get_basename (m.file_path));
                progress.fraction = (double) i / items.length;
                progress.text = "%d of %d".printf (i + 1, items.length);
                progress.show_text = true;
                file_label.label = name;
                try {
                    var src = File.new_for_path (m.file_path);
                    var dest = SaveFolder.unique_destination (folder, name);
                    yield src.copy_async (dest, FileCopyFlags.NONE,
                                          Priority.DEFAULT, cancellable, null);
                    saved++;
                } catch (Error e) {
                    if (e is IOError.CANCELLED) break;
                    failed++;
                }
            }

            finished = true;
            alert.force_close ();
            if (!is_open) return;

            string summary;
            if (cancellable.is_cancelled ()) {
                summary = "Saving cancelled — %d file%s saved".printf (
                    saved, saved == 1 ? "" : "s");
            } else {
                summary = "Saved %d file%s".printf (saved,
                    saved == 1 ? "" : "s");
                if (failed > 0) summary += ", %d failed".printf (failed);
                if (skipped > 0) summary += ", %d not downloaded".printf (skipped);
            }
            toast (summary);
        }

        private void toast (string text) {
            toasts.add_toast (new Adw.Toast (text));
        }
    }
}
