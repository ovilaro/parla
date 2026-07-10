namespace Dc {

    public delegate void SettingWriter (KeyFile kf);

    public const int FONT_SIZE_SYSTEM = 0;
    public const int FONT_SIZE_MIN = 6;
    public const int FONT_SIZE_MAX = 32;
    public const int FONT_SIZE_FALLBACK = 11;

    public enum SidebarMode {
        FULL = 0,
        COMPACT = 1,
        HIDDEN = 2
    }

    public enum ThemeOverride {
        SYSTEM = 0,
        LIGHT = 1,
        DARK = 2;
    }

    public enum MessageStyle {
        BUBBLES = 0,
        IRC = 1;
    }

    public enum BubbleAvatarDisplay {
        NONE = 0,
        OTHER = 1,
        BOTH = 2;
    }

    public enum BackgroundMode {
        SYSTEM = 0,
        SOLID = 1,
        GRADIENT = 2;
    }

    public enum FontAttribute {
        REGULAR = 0,
        ITALIC = 1,
        BOLD = 2,
        BOLD_ITALIC = 3;

        public Pango.Style pango_style () {
            return this == ITALIC || this == BOLD_ITALIC
                ? Pango.Style.ITALIC
                : Pango.Style.NORMAL;
        }

        public Pango.Weight pango_weight () {
            return this == BOLD || this == BOLD_ITALIC
                ? Pango.Weight.BOLD
                : Pango.Weight.NORMAL;
        }

        public string css_style () {
            return pango_style () == Pango.Style.ITALIC ? "italic" : "normal";
        }

        public string css_weight () {
            return pango_weight () == Pango.Weight.BOLD ? "bold" : "normal";
        }
    }

    public class SettingsManager : Object {

        public signal void appearance_changed ();
        public signal void font_changed ();

        public int double_click_action { get; set; default = 0; }
        public bool markdown_rendering { get; set; default = false; }
        public bool shift_enter_sends { get; set; default = false; }
        public bool notifications_enabled { get; set; default = true; }
        public bool show_notification_contents { get; set; default = true; }
        public bool minimize_to_tray { get; set; default = false; }
        public bool system_audio_player { get; set; default = false; }
        public string rpc_server_path { get; set; default = ""; }
        public RpcServerSource rpc_server_source { get; set; default = RpcServerSource.AUTO; }
        public bool rpc_check_updates_on_startup { get; set; default = true; }
        public SidebarMode sidebar_mode { get; set; default = SidebarMode.FULL; }
        public string default_account_addr { get; set; default = ""; }
        public ThemeOverride theme_override { get; set; default = ThemeOverride.SYSTEM; }
        public MessageStyle message_style { get; set; default = MessageStyle.BUBBLES; }
        public BubbleAvatarDisplay bubble_avatar_display { get; set; default = BubbleAvatarDisplay.NONE; }
        public bool bubble_avatars_in_direct_chats { get; set; default = false; }
        public string accent_color { get; set; default = ""; }
        public BackgroundMode background_mode { get; set; default = BackgroundMode.SYSTEM; }
        public string background_color { get; set; default = ""; }
        public string font_family { get; set; default = ""; }
        public FontAttribute font_attribute { get; set; default = FontAttribute.REGULAR; }
        public int font_size { get; set; default = FONT_SIZE_SYSTEM; }

        public static string get_config_path () {
            return Path.build_filename (
                Environment.get_user_config_dir (),
                "parla", "settings.ini");
        }

        /**
         * True when this build pins the deltachat-rpc-server to a fixed binary
         * (meson -Drpc_server_path=...). Such builds always use that binary as
         * the Custom server and never auto-update the engine.
         */
        public static bool rpc_server_path_is_fixed () {
            return Parla.RPC_SERVER_PATH.length > 0;
        }

        /** Server path to actually use: the pinned one if set, else the user's. */
        public string effective_rpc_server_path () {
            return rpc_server_path_is_fixed ()
                ? Parla.RPC_SERVER_PATH : rpc_server_path;
        }

        /** Server source to actually use: Custom when pinned, else the user's. */
        public RpcServerSource effective_rpc_server_source () {
            return rpc_server_path_is_fixed ()
                ? RpcServerSource.CUSTOM : rpc_server_source;
        }

        /** Whether Parla may check for / install engine updates. */
        public bool rpc_auto_update_enabled () {
            return !rpc_server_path_is_fixed () && rpc_check_updates_on_startup;
        }

        public void load () {
            var kf = new KeyFile ();
            try { kf.load_from_file (get_config_path (), KeyFileFlags.NONE); }
            catch (Error e) { /* file may not exist — helpers return defaults */ }
            double_click_action = kf_enum (kf, "double_click_action", 0, 5);
            markdown_rendering = kf_bool (kf, "markdown_rendering", false);
            Markdown.enabled = markdown_rendering;
            shift_enter_sends = kf_bool (kf, "shift_enter_sends", false);
            notifications_enabled = kf_bool (kf, "notifications_enabled", true);
            show_notification_contents =
                kf_bool (kf, "show_notification_contents", true);
            minimize_to_tray = kf_bool (kf, "minimize_to_tray", false);
            system_audio_player = kf_bool (kf, "system_audio_player", false);
            AudioPlayer.prefer_system = system_audio_player;
            rpc_server_path = kf_str (kf, "rpc_server_path", "");
            int source = kf_enum (kf, "rpc_server_source",
                                  (int) RpcServerSource.AUTO, 1);
            rpc_server_source = (RpcServerSource) source;
            rpc_check_updates_on_startup =
                kf_bool (kf, "rpc_check_updates_on_startup", true);
            int sb = kf_enum (kf, "sidebar_mode", (int) SidebarMode.FULL, 2);
            sidebar_mode = (SidebarMode) sb;
            default_account_addr = kf_str (kf, "default_account_addr", "");
            int theme = kf_enum (kf, "theme_override",
                                 (int) ThemeOverride.SYSTEM, 2);
            theme_override = (ThemeOverride) theme;
            int ms = kf_enum (kf, "message_style",
                              (int) MessageStyle.BUBBLES, 1);
            message_style = (MessageStyle) ms;
            int bad = kf_enum (kf, "bubble_avatar_display",
                               (int) BubbleAvatarDisplay.NONE, 2);
            bubble_avatar_display = (BubbleAvatarDisplay) bad;
            bubble_avatars_in_direct_chats =
                kf_bool (kf, "bubble_avatars_in_direct_chats", false);
            accent_color = kf_str (kf, "accent_color", "");
            int bm = kf_enum (kf, "background_mode",
                              (int) BackgroundMode.SYSTEM, 2);
            background_mode = (BackgroundMode) bm;
            background_color = kf_str (kf, "background_color", "");
            font_family = kf_str (kf, "font_family", "").strip ();
            int fa = kf_enum (kf, "font_attribute",
                              (int) FontAttribute.REGULAR, 3);
            font_attribute = (FontAttribute) fa;
            font_size = clamp_font_size (kf_int (kf, "font_size",
                                                 FONT_SIZE_SYSTEM));
        }

        private static int kf_int (KeyFile kf, string k, int d) {
            try { return kf.get_integer ("General", k); } catch { return d; }
        }

        private static bool kf_bool (KeyFile kf, string k, bool d) {
            try { return kf.get_boolean ("General", k); } catch { return d; }
        }

        private static string kf_str (KeyFile kf, string k, string d) {
            try { return kf.get_string ("General", k); } catch { return d; }
        }

        private static int kf_enum (KeyFile kf, string k, int d, int max) {
            int v = kf_int (kf, k, d);
            return v >= 0 && v <= max ? v : d;
        }

        public void save_double_click_action (int v) {
            double_click_action = v;
            save_int ("double_click_action", v);
        }

        public void save_markdown_rendering (bool v) {
            markdown_rendering = v; Markdown.enabled = v;
            save_bool ("markdown_rendering", v);
        }

        public void save_shift_enter_sends (bool v) {
            shift_enter_sends = v;
            save_bool ("shift_enter_sends", v);
        }

        public void save_notifications_enabled (bool v) {
            notifications_enabled = v;
            save_bool ("notifications_enabled", v);
        }

        public void save_show_notification_contents (bool v) {
            show_notification_contents = v;
            save_bool ("show_notification_contents", v);
        }

        public void save_minimize_to_tray (bool v) {
            minimize_to_tray = v;
            save_bool ("minimize_to_tray", v);
        }

        public void save_system_audio_player (bool v) {
            system_audio_player = v;
            AudioPlayer.prefer_system = v;
            save_bool ("system_audio_player", v);
        }

        public void save_rpc_server_path (string v) {
            rpc_server_path = v;
            save_string ("rpc_server_path", v);
        }

        public void save_rpc_server_source (RpcServerSource v) {
            rpc_server_source = v;
            save_int ("rpc_server_source", (int) v);
        }

        public void save_rpc_check_updates_on_startup (bool v) {
            rpc_check_updates_on_startup = v;
            save_bool ("rpc_check_updates_on_startup", v);
        }

        public void save_sidebar_mode (SidebarMode v) {
            sidebar_mode = v;
            save_int ("sidebar_mode", (int) v);
        }

        public void save_default_account_addr (string v) {
            default_account_addr = v;
            save_string ("default_account_addr", v);
        }

        public void save_theme_override (ThemeOverride v) {
            theme_override = v;
            save_int ("theme_override", (int) v);
        }

        public void save_message_style (MessageStyle v) {
            message_style = v;
            save_int ("message_style", (int) v);
            appearance_changed ();
        }

        public void save_bubble_avatar_display (BubbleAvatarDisplay v) {
            bubble_avatar_display = v;
            save_int ("bubble_avatar_display", (int) v);
            appearance_changed ();
        }

        public void save_bubble_avatars_in_direct_chats (bool v) {
            bubble_avatars_in_direct_chats = v;
            save_bool ("bubble_avatars_in_direct_chats", v);
            appearance_changed ();
        }

        public void save_accent_color (string v) {
            accent_color = v;
            save_string ("accent_color", v);
            appearance_changed ();
        }

        /* The background is pure window CSS — it does not affect message
           widgets, so (unlike accent/message-style) these do NOT emit
           appearance_changed; the dialog applies the change directly,
           avoiding a needless rebuild of every conversation view. */
        public void save_background_mode (BackgroundMode v) {
            background_mode = v;
            save_int ("background_mode", (int) v);
        }

        public void save_background_color (string v) {
            background_color = v;
            save_string ("background_color", v);
        }

        public void save_font_size (int v) {
            save_font (font_family, font_attribute, v);
        }

        public void save_font_description (Pango.FontDescription desc) {
            string family = desc.get_family () ?? "";
            save_font (family, attribute_from_font_description (desc),
                       size_from_font_description (desc));
        }

        public void reset_font_defaults () {
            save_font ("", FontAttribute.REGULAR, FONT_SIZE_SYSTEM);
        }

        private void save_font (string family, FontAttribute attr, int size) {
            string clean_family = family.strip ();
            int clean_size = clamp_font_size (size);
            if (font_family == clean_family &&
                font_attribute == attr &&
                font_size == clean_size) {
                return;
            }

            font_family = clean_family;
            font_attribute = attr;
            font_size = clean_size;
            save_to_file ((kf) => {
                kf.set_string ("General", "font_family", font_family);
                kf.set_integer ("General", "font_attribute",
                                (int) font_attribute);
                kf.set_integer ("General", "font_size", font_size);
            });
            font_changed ();
        }

        public static int clamp_font_size (int size) {
            if (size <= FONT_SIZE_SYSTEM) return FONT_SIZE_SYSTEM;
            if (size < FONT_SIZE_MIN) return FONT_SIZE_MIN;
            if (size > FONT_SIZE_MAX) return FONT_SIZE_MAX;
            return size;
        }

        public static int system_font_size () {
            string font_name = system_font_name ();
            var desc = Pango.FontDescription.from_string (font_name);
            int size = size_from_font_description (desc);
            return size > 0 ? clamp_font_size (size) : FONT_SIZE_FALLBACK;
        }

        public int effective_font_size () {
            return font_size > 0 ? font_size : system_font_size ();
        }

        public Pango.FontDescription effective_font_description () {
            var desc = Pango.FontDescription.from_string (
                font_family.length > 0 ? font_family : system_font_name ());
            desc.set_style (font_attribute.pango_style ());
            desc.set_weight (font_attribute.pango_weight ());
            desc.set_size (effective_font_size () * Pango.SCALE);
            return desc;
        }

        private static string system_font_name () {
            var gtk_settings = Gtk.Settings.get_default ();
            if (gtk_settings == null || gtk_settings.gtk_font_name.length == 0) {
                return "Sans %d".printf (FONT_SIZE_FALLBACK);
            }
            return gtk_settings.gtk_font_name;
        }

        private static int size_from_font_description (
                Pango.FontDescription desc) {
            int size = desc.get_size ();
            if (size <= 0) return FONT_SIZE_SYSTEM;
            return (size + (Pango.SCALE / 2)) / Pango.SCALE;
        }

        private static FontAttribute attribute_from_font_description (
                Pango.FontDescription desc) {
            bool italic = desc.get_style () == Pango.Style.ITALIC ||
                desc.get_style () == Pango.Style.OBLIQUE;
            bool bold = ((int) desc.get_weight ()) >=
                ((int) Pango.Weight.BOLD);
            if (italic && bold) return FontAttribute.BOLD_ITALIC;
            if (italic) return FontAttribute.ITALIC;
            if (bold) return FontAttribute.BOLD;
            return FontAttribute.REGULAR;
        }

        private void save_int (string key, int value) {
            save_to_file ((kf) => { kf.set_integer ("General", key, value); });
        }

        private void save_bool (string key, bool value) {
            save_to_file ((kf) => { kf.set_boolean ("General", key, value); });
        }

        private void save_string (string key, string value) {
            save_to_file ((kf) => { kf.set_string ("General", key, value); });
        }

        public void save_to_file (SettingWriter writer) {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (get_config_path (), KeyFileFlags.NONE);
            } catch (Error e) { /* file may not exist yet */ }
            writer (kf);
            try {
                var dir = Path.get_dirname (get_config_path ());
                DirUtils.create_with_parents (dir, 0755);
                kf.save_to_file (get_config_path ());
            } catch (Error e) {
                warning ("Failed to save settings: %s", e.message);
            }
        }
    }

    public class SettingsDialog : Adw.Dialog {

        private Gtk.Box content;
        private unowned Window app_window;
        private RpcClient rpc;
        private Adw.ActionRow proxy_switch_row;
        private Adw.ActionRow proxy_url_row;
        private Gtk.Switch proxy_switch;
        private Gtk.Entry proxy_entry;
        private Adw.ActionRow rpc_row;
        private Adw.ActionRow rpc_version_row;
        private Gtk.DropDown rpc_source_dropdown;
        private Gtk.Button rpc_choose_btn;
        private Gtk.Button rpc_download_btn;
        private Gtk.Button rpc_update_btn;
        private bool loading_proxy = false;
        private bool saving_proxy = false;
        private bool saved_proxy_enabled = false;
        private string saved_proxy_url = "";
        private bool syncing_rpc_source = false;
        private bool syncing_font_controls = false;
        private Adw.ActionRow font_type_row;
        private Gtk.FontDialogButton font_btn;
        private uint rpc_version_request = 0;
        private string? rpc_current_version = null;
        private bool rpc_update_check_available = false;

        public SettingsDialog (Window window, RpcClient rpc) {
            this.app_window = window;
            this.rpc = rpc;
            this.title = "Settings";
            this.content_width = 400;
            this.content_height = 480;

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            var header = new Adw.HeaderBar ();
            header.show_end_title_buttons = true;
            box.append (header);

            content = new Gtk.Box (Gtk.Orientation.VERTICAL, 16);
            content.margin_start = 16;
            content.margin_end = 16;
            content.margin_top = 12;
            content.margin_bottom = 16;

            var appearance_list = settings_list ("Appearance");

            var theme_row = action_row (
                "GTK theme",
                "Override the system light or dark theme");

            string[] theme_labels = { "System", "Light", "Dark" };
            var theme_combo = row_dropdown (theme_row, theme_labels,
                (uint) app_window.settings.theme_override);
            theme_combo.notify["selected"].connect (() => {
                app_window.settings.save_theme_override (
                    (ThemeOverride) theme_combo.selected);
                apply_theme_override ();
            });
            appearance_list.append (theme_row);

            var style_row = action_row (
                "Message style",
                "Use chat bubbles or compact IRC-style lines");

            string[] style_labels = { "Bubbles", "IRC" };
            var style_combo = row_dropdown (style_row, style_labels,
                (uint) app_window.settings.message_style);
            style_combo.notify["selected"].connect (() => {
                app_window.settings.save_message_style (
                    (MessageStyle) style_combo.selected);
            });
            appearance_list.append (style_row);

            var avatar_row = action_row (
                "Bubble avatars",
                "Show small avatars beside message bubbles");

            string[] avatar_labels = { "none", "other", "both" };
            var avatar_combo = row_dropdown (avatar_row, avatar_labels,
                (uint) app_window.settings.bubble_avatar_display);
            avatar_combo.notify["selected"].connect (() => {
                app_window.settings.save_bubble_avatar_display (
                    (BubbleAvatarDisplay) avatar_combo.selected);
            });
            appearance_list.append (avatar_row);

            var direct_avatar_row = action_row (
                "Use avatars in 1:1 chats",
                "Use the bubble avatar setting in direct conversations");
            var direct_avatar_check = new Gtk.CheckButton ();
            direct_avatar_check.active =
                app_window.settings.bubble_avatars_in_direct_chats;
            direct_avatar_check.toggled.connect (() => {
                app_window.settings.save_bubble_avatars_in_direct_chats (
                    direct_avatar_check.active);
            });
            direct_avatar_row.add_suffix (direct_avatar_check);
            direct_avatar_row.activatable_widget = direct_avatar_check;
            appearance_list.append (direct_avatar_row);

            font_type_row = action_row (
                "Conversation font",
                "Use the system font or choose another family, style and size");
            var font_dialog = new Gtk.FontDialog ();
            font_dialog.title = "Choose Font";
            font_dialog.modal = true;
            font_btn = new Gtk.FontDialogButton (font_dialog);
            font_btn.valign = Gtk.Align.CENTER;
            font_btn.use_font = false;
            font_btn.use_size = false;
            font_btn.font_desc = app_window.settings.effective_font_description ();
            font_btn.notify["font-desc"].connect (() => {
                if (syncing_font_controls) return;
                var desc = font_btn.get_font_desc ();
                if (desc != null) {
                    app_window.settings.save_font_description (desc);
                    sync_font_controls ();
                }
            });
            font_type_row.add_suffix (font_btn);

            var font_reset_btn = new Gtk.Button.from_icon_name ("edit-undo-symbolic");
            font_reset_btn.valign = Gtk.Align.CENTER;
            font_reset_btn.add_css_class ("flat");
            font_reset_btn.tooltip_text = "Reset font settings to defaults";
            font_reset_btn.clicked.connect (() => {
                app_window.settings.reset_font_defaults ();
                sync_font_controls ();
            });
            font_type_row.add_suffix (font_reset_btn);
            appearance_list.append (font_type_row);

            sync_font_controls ();

            var accent_row = action_row (
                "Accent color",
                "Override the system accent color");

            var accent_btn = new Gtk.ColorDialogButton (new Gtk.ColorDialog ());
            accent_btn.valign = Gtk.Align.CENTER;
            apply_hex_to_button (accent_btn, app_window.settings.accent_color);
            accent_btn.notify["rgba"].connect (() => {
                app_window.settings.save_accent_color (
                    hex_from_rgba (accent_btn.get_rgba ()));
            });

            var accent_reset_btn = new Gtk.Button.from_icon_name ("edit-undo-symbolic");
            accent_reset_btn.valign = Gtk.Align.CENTER;
            accent_reset_btn.add_css_class ("flat");
            accent_reset_btn.tooltip_text = "Use system accent color";
            accent_reset_btn.clicked.connect (() => {
                app_window.settings.save_accent_color ("");
                apply_hex_to_button (accent_btn, "");
            });

            accent_row.add_suffix (accent_btn);
            accent_row.add_suffix (accent_reset_btn);
            appearance_list.append (accent_row);

            var bg_row = action_row (
                "Background color",
                "Tint the window background with a solid color or a gradient");

            string[] bg_mode_labels = { "System", "Solid", "Gradient" };
            var bg_mode_combo = row_dropdown (bg_row, bg_mode_labels,
                (uint) app_window.settings.background_mode);

            var bg_color_btn = new Gtk.ColorDialogButton (new Gtk.ColorDialog ());
            bg_color_btn.valign = Gtk.Align.CENTER;
            apply_hex_to_button (bg_color_btn, app_window.settings.background_color);
            /* The picker only matters for Solid/Gradient; dim it for System. */
            bg_color_btn.sensitive =
                app_window.settings.background_mode != BackgroundMode.SYSTEM;

            bg_mode_combo.notify["selected"].connect (() => {
                var mode = (BackgroundMode) bg_mode_combo.selected;
                bg_color_btn.sensitive = mode != BackgroundMode.SYSTEM;
                app_window.settings.save_background_mode (mode);
                apply_background ();
            });
            bg_color_btn.notify["rgba"].connect (() => {
                app_window.settings.save_background_color (
                    hex_from_rgba (bg_color_btn.get_rgba ()));
                apply_background ();
            });

            bg_row.add_suffix (bg_color_btn);
            appearance_list.append (bg_row);

            var behavior_list = settings_list ("Behavior");

            var dblclick_row = action_row (
                "Double-click on message",
                "Action when a message is double-clicked");

            string[] dblclick_labels = {
                "Reply to message",
                "React with ❤️",
                "React with 👍",
                "Open user profile",
                "Open context menu",
                "Do nothing"
            };

            uint dblclick_selected = (uint) app_window.settings.double_click_action;
            if (dblclick_selected == 4) dblclick_selected = 5;
            else if (dblclick_selected == 5) dblclick_selected = 4;
            var dblclick_combo = row_dropdown (dblclick_row, dblclick_labels,
                dblclick_selected);
            dblclick_combo.notify["selected"].connect (() => {
                uint selected = dblclick_combo.selected;
                int action = (int) selected;
                if (selected == 4) action = 5;
                else if (selected == 5) action = 4;
                app_window.settings.save_double_click_action (action);
            });

            behavior_list.append (dblclick_row);

            var md_row = action_row (
                "Markdown rendering",
                "Format bold, italic, code and headings");
            var md_switch = row_switch (md_row, Markdown.enabled);
            md_switch.notify["active"].connect (() => {
                app_window.settings.save_markdown_rendering (md_switch.active);
            });

            var shift_row = action_row (
                "Shift+Return sends message",
                "When on, Return inserts a newline and Shift+Return sends");
            var shift_switch = row_switch (
                shift_row, app_window.settings.shift_enter_sends);
            shift_switch.notify["active"].connect (() => {
                app_window.settings.save_shift_enter_sends (shift_switch.active);
            });

            behavior_list.append (shift_row);

            var audio_row = action_row (
                "System audio player",
                "Spawn afplay/gst-play/mpv to play voice messages instead of "
                + "the built-in GTK media backend");
            var audio_switch = row_switch (
                audio_row, app_window.settings.system_audio_player);
            audio_switch.notify["active"].connect (() => {
                app_window.settings.save_system_audio_player (audio_switch.active);
            });

            /* The tray is a StatusNotifierItem exported over the session
               D-Bus with no watcher on macOS, so the option is Linux-only. */
            if (!Platform.is_macos ()) {
                var tray_row = action_row (
                    "Minimize to status bar",
                    "Closing the window keeps Parla running in the status bar; "
                    + "notifications still appear");
                var tray_switch = row_switch (
                    tray_row, app_window.settings.minimize_to_tray);
                tray_switch.notify["active"].connect (() => {
                    app_window.set_minimize_to_tray (tray_switch.active);
                });

                behavior_list.append (tray_row);
            }

            var notifications_list = settings_list ("Notifications");
            var notif_row = action_row (
                "Desktop notifications",
                "Notify on incoming messages when the window is not focused");
            var notif_switch = row_switch (
                notif_row, app_window.settings.notifications_enabled);
            notif_switch.notify["active"].connect (() => {
                app_window.set_notifications_enabled (notif_switch.active);
            });

            notifications_list.append (notif_row);


            var notification_contents_row = action_row (
                "Show message contents in notifications",
                "Include sender text and attachment names in desktop notifications");
            var notification_contents_switch = row_switch (
                notification_contents_row,
                app_window.settings.show_notification_contents);
            notification_contents_switch.notify["active"].connect (() => {
                app_window.settings.save_show_notification_contents (
                    notification_contents_switch.active);
            });
            notifications_list.append (notification_contents_row);

            var network_list = settings_list ("Network");

            proxy_switch_row = action_row (
                "Use Proxy",
                "Route this profile through the configured proxy");
            proxy_switch = row_switch (proxy_switch_row, false);
            proxy_switch.notify["active"].connect (() => {
                if (!loading_proxy) save_proxy_settings.begin ();
            });
            network_list.append (proxy_switch_row);

            proxy_url_row = action_row (
                "Proxy URL",
                "socks5://, http://, https://, or ss://");

            proxy_entry = new Gtk.Entry ();
            proxy_entry.placeholder_text = "socks5://127.0.0.1:9050";
            proxy_entry.input_purpose = Gtk.InputPurpose.URL;
            proxy_entry.hexpand = true;
            proxy_entry.valign = Gtk.Align.CENTER;
            proxy_entry.activate.connect (() => { save_proxy_settings.begin (); });
            var proxy_focus = new Gtk.EventControllerFocus ();
            proxy_focus.leave.connect (() => { save_proxy_settings.begin (); });
            proxy_entry.add_controller (proxy_focus);
            proxy_url_row.add_suffix (proxy_entry);
            proxy_url_row.activatable_widget = proxy_entry;
            network_list.append (proxy_url_row);

            load_proxy_settings.begin ();

            var advanced_list = settings_list ("Advanced");
            advanced_list.append (md_row);
            advanced_list.append (audio_row);

            var chatmail_list = settings_list ("Chatmail");

            rpc_row = action_row ("Chatmail Server");

            string[] rpc_source_labels = { "Auto", "Custom" };
            rpc_source_dropdown = row_dropdown (rpc_row, rpc_source_labels,
                (uint) app_window.settings.effective_rpc_server_source ());
            rpc_source_dropdown.notify["selected"].connect (on_rpc_source_changed);

            rpc_choose_btn = new Gtk.Button.with_label ("Choose");
            rpc_choose_btn.valign = Gtk.Align.CENTER;
            rpc_choose_btn.add_css_class ("flat");
            rpc_choose_btn.tooltip_text = "Choose a deltachat-rpc-server binary";
            rpc_choose_btn.clicked.connect (() => { on_browse_rpc_server.begin (); });
            rpc_row.add_suffix (rpc_choose_btn);

            rpc_download_btn = new Gtk.Button.with_label ("Install");
            rpc_download_btn.valign = Gtk.Align.CENTER;
            rpc_download_btn.add_css_class ("flat");
            rpc_download_btn.tooltip_text =
                "Download the latest deltachat-rpc-server into Parla's data dir";
            rpc_download_btn.clicked.connect (() => { install_managed_server.begin (); });
            rpc_row.add_suffix (rpc_download_btn);

            chatmail_list.append (rpc_row);

            rpc_version_row = action_row ("Chatmail server version", "Checking...");
            rpc_update_btn = new Gtk.Button.with_label ("Check");
            rpc_update_btn.valign = Gtk.Align.CENTER;
            rpc_update_btn.add_css_class ("flat");
            rpc_update_btn.tooltip_text = "Check latest deltachat-rpc-server release";
            rpc_update_btn.clicked.connect (() => { check_rpc_updates.begin (); });
            rpc_version_row.add_suffix (rpc_update_btn);
            chatmail_list.append (rpc_version_row);

            var rpc_autocheck_row = action_row (
                "Check for chatmail updates on startup",
                "Notify when a newer deltachat-rpc-server is available");
            var autocheck_switch = row_switch (
                rpc_autocheck_row,
                app_window.settings.rpc_check_updates_on_startup);
            autocheck_switch.notify["active"].connect (() => {
                app_window.settings.save_rpc_check_updates_on_startup (
                    autocheck_switch.active);
            });
            /* Engine updates are off entirely when the server path is pinned. */
            rpc_autocheck_row.visible = !SettingsManager.rpc_server_path_is_fixed ();
            chatmail_list.append (rpc_autocheck_row);

            update_rpc_row ();

            var reset_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            reset_box.margin_top = 8;

            var reset_btn = new Gtk.Button.with_label ("Factory Reset");
            reset_btn.add_css_class ("destructive-action");
            reset_btn.tooltip_text = "Delete all Parla configuration and start fresh";
            reset_btn.clicked.connect (on_reset_settings);
            reset_box.append (reset_btn);

            var reset_label = new Gtk.Label ("Remove all settings and close the app");
            reset_label.add_css_class ("dim-label");
            reset_label.valign = Gtk.Align.CENTER;
            reset_box.append (reset_label);

            content.append (reset_box);

            var scroll = new Gtk.ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scroll.child = content;
            box.append (scroll);

            this.child = box;
        }

        private Gtk.ListBox settings_list (string title) {
            var label = new Gtk.Label (title);
            label.add_css_class ("title-3");
            label.halign = Gtk.Align.START;
            content.append (label);

            var list = new Gtk.ListBox ();
            list.selection_mode = Gtk.SelectionMode.NONE;
            list.add_css_class ("boxed-list");
            content.append (list);
            return list;
        }

        private static Adw.ActionRow action_row (string title,
                                                 string? subtitle = null) {
            var row = new Adw.ActionRow ();
            row.title = title;
            if (subtitle != null) row.subtitle = subtitle;
            return row;
        }

        private static Gtk.Switch row_switch (Adw.ActionRow row, bool active) {
            var sw = new Gtk.Switch ();
            sw.active = active;
            sw.valign = Gtk.Align.CENTER;
            row.add_suffix (sw);
            row.activatable_widget = sw;
            return sw;
        }

        private static Gtk.DropDown row_dropdown (Adw.ActionRow row, string[] labels,
                                                  uint selected) {
            var dropdown = new Gtk.DropDown.from_strings (labels);
            dropdown.selected = selected;
            dropdown.valign = Gtk.Align.CENTER;
            row.add_suffix (dropdown);
            row.activatable_widget = dropdown;
            return dropdown;
        }

        private void sync_font_controls () {
            syncing_font_controls = true;

            string family = app_window.settings.font_family;
            font_type_row.subtitle = family.length > 0
                ? family
                : "System default";
            font_type_row.tooltip_text = family.length > 0 ? family : null;
            font_btn.font_desc = app_window.settings.effective_font_description ();

            syncing_font_controls = false;
        }

        private static string hex_from_rgba (Gdk.RGBA c) {
            return "#%02x%02x%02x".printf (
                (uint) (c.red * 255), (uint) (c.green * 255),
                (uint) (c.blue * 255));
        }

        private async void load_proxy_settings () {
            if (!rpc.is_connected || rpc.account_id <= 0) {
                set_proxy_controls_sensitive (false);
                proxy_switch_row.subtitle = "No active profile";
                proxy_url_row.subtitle = "No active profile";
                return;
            }

            loading_proxy = true;
            set_proxy_controls_sensitive (false);

            try {
                string? enabled = yield rpc.get_config ("proxy_enabled",
                                                        rpc.account_id);
                string? proxy_url = yield rpc.get_config ("proxy_url",
                                                          rpc.account_id);
                string first = first_proxy_url (proxy_url ?? "");
                proxy_switch.active = (enabled ?? "") == "1";
                proxy_entry.text = first;
                saved_proxy_enabled = proxy_switch.active;
                saved_proxy_url = first;

                proxy_switch_row.subtitle = proxy_switch.active
                    ? "Enabled for current profile"
                    : "Disabled for current profile";
                proxy_url_row.subtitle = "socks5://, http://, https://, or ss://";
                proxy_url_row.tooltip_text = first.length > 0 ? first : null;
            } catch (Error e) {
                proxy_switch_row.subtitle = "Unable to read proxy settings";
                proxy_url_row.tooltip_text = e.message;
            } finally {
                loading_proxy = false;
                set_proxy_controls_sensitive (true);
            }
        }

        private void set_proxy_controls_sensitive (bool sensitive) {
            bool active = sensitive && rpc.is_connected && rpc.account_id > 0;
            proxy_switch.sensitive = active;
            proxy_entry.sensitive = active;
        }

        private static string first_proxy_url (string urls) {
            foreach (string line in urls.split ("\n")) {
                string s = line.strip ();
                if (s.length > 0) return s;
            }
            return "";
        }

        private async string? normalize_proxy_url (string url) {
            try {
                var qr = yield rpc.check_qr (rpc.account_id, url);
                if (qr == null || !qr.has_member ("kind") ||
                    qr.get_string_member ("kind") != "proxy") {
                    show_error (this, "Invalid proxy URL: " + url);
                    return null;
                }
                return qr.has_member ("url") ? qr.get_string_member ("url") : url;
            } catch (Error e) {
                show_error (this, "Invalid proxy URL: %s\n%s".printf (
                    url, e.message));
                return null;
            }
        }

        private async void save_proxy_settings () {
            if (loading_proxy || saving_proxy) return;

            if (!rpc.is_connected || rpc.account_id <= 0) {
                app_window.show_toast ("No active profile");
                return;
            }

            string url = proxy_entry.text.strip ();
            bool enabled = proxy_switch.active;

            if (enabled == saved_proxy_enabled && url == saved_proxy_url) {
                return;
            }

            if (enabled && url.length == 0) {
                show_error (this, "Enter a proxy URL before enabling the proxy.");
                loading_proxy = true;
                proxy_switch.active = false;
                loading_proxy = false;
                enabled = false;
                if (!saved_proxy_enabled && saved_proxy_url.length == 0) {
                    return;
                }
            }

            saving_proxy = true;
            set_proxy_controls_sensitive (false);

            if (url.length > 0) {
                string? normalized = yield normalize_proxy_url (url);
                if (normalized == null) {
                    saving_proxy = false;
                    set_proxy_controls_sensitive (true);
                    return;
                }
                url = normalized;
                proxy_entry.text = url;
            }

            try {
                yield rpc.batch_set_config ("proxy_url", url, rpc.account_id);
                yield rpc.batch_set_config ("proxy_enabled",
                                            enabled ? "1" : "0",
                                            rpc.account_id);
                yield rpc.stop_io (rpc.account_id);
                yield rpc.start_io (rpc.account_id);

                proxy_switch_row.subtitle = enabled
                    ? "Enabled for current profile"
                    : "Disabled for current profile";
                proxy_url_row.tooltip_text = url.length > 0 ? url : null;
                saved_proxy_enabled = enabled;
                saved_proxy_url = url;
                app_window.show_toast ("Proxy settings saved");
            } catch (Error e) {
                show_error (this, "Failed to save proxy settings: " + e.message);
            } finally {
                saving_proxy = false;
                set_proxy_controls_sensitive (true);
            }
        }

        private void update_rpc_row () {
            sync_rpc_source_dropdown ();

            bool pinned = SettingsManager.rpc_server_path_is_fixed ();
            string custom = app_window.settings.effective_rpc_server_path ();
            RpcServerSource source = app_window.settings.effective_rpc_server_source ();
            string? found = AccountFinder.find_rpc_server (custom, source);
            /* A pinned build can't change source or update the engine. */
            rpc_source_dropdown.sensitive = !pinned;
            rpc_choose_btn.visible = source == RpcServerSource.CUSTOM && !pinned;
            rpc_choose_btn.sensitive = source == RpcServerSource.CUSTOM && !pinned;
            rpc_download_btn.visible = source == RpcServerSource.AUTO && !pinned;
            rpc_download_btn.sensitive = RpcInstaller.can_auto_install () && !pinned;
            rpc_download_btn.label =
                found == AccountFinder.get_managed_rpc_path () ? "Update" : "Install";
            rpc_update_btn.visible = !pinned;
            switch (source) {
            case RpcServerSource.CUSTOM:
                if (custom.length == 0) {
                    rpc_row.subtitle = "No custom binary selected";
                    rpc_row.tooltip_text = "Choose a deltachat-rpc-server binary";
                } else {
                    rpc_row.subtitle = found != null
                        ? (pinned ? "Using built-in server" : "Using custom binary")
                        : "Custom path is not executable";
                    rpc_row.tooltip_text = custom;
                }
                break;
            case RpcServerSource.AUTO:
            default:
                rpc_row.subtitle = found != null
                    ? "Using Parla or system server"
                    : "Standalone server not found";
                rpc_row.tooltip_text = found
                    ?? "Install deltachat-rpc-server or choose a custom binary";
                break;
            }
            update_rpc_version_row.begin (found);
        }

        private async void update_rpc_version_row (string? rpc_path) {
            uint request_id = ++rpc_version_request;
            if (rpc_path == null || rpc_path.length == 0) {
                rpc_version_row.subtitle = "Not available";
                rpc_version_row.tooltip_text = "No executable server selected";
                rpc_current_version = null;
                rpc_update_check_available = false;
                rpc_update_btn.sensitive = false;
                return;
            }

            rpc_version_row.subtitle = "Checking...";
            rpc_version_row.tooltip_text = rpc_path;
            rpc_current_version = null;
            rpc_update_check_available = false;
            rpc_update_btn.sensitive = false;

            try {
                string? stdout_buf;
                string? stderr_buf;
                bool successful;
#if WINDOWS
                var run = yield Platform.run_hidden ({ rpc_path, "--version" });
                stdout_buf = run.output;
                stderr_buf = run.errout;
                successful = run.status == 0;
#else
                var process = new Subprocess (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                    rpc_path, "--version");
                yield process.communicate_utf8_async (
                    null, null, out stdout_buf, out stderr_buf);
                successful = process.get_successful ();
#endif

                if (request_id != rpc_version_request) return;

                string version = ((stdout_buf ?? "").strip ().length > 0)
                    ? (stdout_buf ?? "").strip ()
                    : (stderr_buf ?? "").strip ();
                if (successful && version.length > 0) {
                    rpc_version_row.subtitle = version;
                    rpc_current_version = RpcInstaller.extract_version (version);
                    rpc_update_check_available =
                        !SettingsManager.rpc_server_path_is_fixed ();
                    rpc_update_btn.sensitive = rpc_update_check_available;
                } else {
                    rpc_version_row.subtitle = "Unable to read version";
                    rpc_current_version = null;
                    rpc_update_check_available = false;
                    rpc_update_btn.sensitive = false;
                }
            } catch (Error e) {
                if (request_id != rpc_version_request) return;
                rpc_version_row.subtitle = "Unable to read version";
                rpc_version_row.tooltip_text = "%s\n%s".printf (rpc_path, e.message);
                rpc_current_version = null;
                rpc_update_check_available = false;
                rpc_update_btn.sensitive = false;
            }
        }

        private async void check_rpc_updates () {
            if (rpc_update_btn == null || !rpc_update_btn.sensitive) return;

            rpc_update_btn.sensitive = false;
            string previous_subtitle = rpc_version_row.subtitle;
            rpc_version_row.subtitle = "Checking for updates...";

            try {
                string latest_tag = yield RpcInstaller.fetch_latest_tag ();
                string? latest_version = RpcInstaller.extract_version (latest_tag);
                if (latest_version == null) {
                    rpc_version_row.subtitle = previous_subtitle;
                    app_window.show_toast ("Could not parse latest RPC server version");
                    return;
                }

                bool managed_active =
                    AccountFinder.find_rpc_server (
                        app_window.settings.effective_rpc_server_path (),
                        app_window.settings.effective_rpc_server_source ())
                    == AccountFinder.get_managed_rpc_path ();

                if (rpc_current_version == null) {
                    rpc_version_row.subtitle =
                        "Latest available: %s".printf (latest_version);
                    app_window.show_toast ("Latest RPC server: " + latest_version);
                } else if (rpc_current_version != latest_version) {
                    rpc_version_row.subtitle = "Latest: %s (installed %s)".printf (
                        latest_version, rpc_current_version);
                    if (managed_active) {
                        app_window.show_toast (
                            "Update available: %s — press Install to update".printf (
                                latest_version));
                    } else {
                        app_window.show_toast (
                            "Chatmail server version differs: " + latest_version);
                    }
                } else {
                    rpc_version_row.subtitle = "Up to date: %s".printf (rpc_current_version);
                    app_window.show_toast ("Chatmail server is up to date");
                }
                rpc_version_row.tooltip_text =
                    "Latest release: https://github.com/chatmail/core/releases/tag/%s".printf (
                        latest_tag);
            } catch (Error e) {
                rpc_version_row.subtitle = previous_subtitle;
                app_window.show_toast ("Update check failed: " + e.message);
            } finally {
                rpc_update_btn.sensitive = rpc_update_check_available;
            }
        }

        private void sync_rpc_source_dropdown () {
            syncing_rpc_source = true;
            rpc_source_dropdown.selected =
                (uint) app_window.settings.effective_rpc_server_source ();
            syncing_rpc_source = false;
        }

        private void on_rpc_source_changed () {
            if (syncing_rpc_source) return;

            RpcServerSource source = (RpcServerSource) rpc_source_dropdown.selected;
            if (source == RpcServerSource.CUSTOM &&
                app_window.settings.rpc_server_path.length == 0) {
                on_browse_rpc_server.begin ();
                return;
            }

            app_window.settings.save_rpc_server_source (source);
            app_window.show_toast ("Chatmail server preference saved");
            update_rpc_row ();
            app_window.reconnect_rpc_server.begin ();
        }

        private async void on_browse_rpc_server () {
            var dlg = new Gtk.FileDialog ();
            dlg.title = "Locate deltachat-rpc-server";
            dlg.modal = true;

            string start = app_window.settings.rpc_server_path;
            if (start.length == 0) start = AccountFinder.find_rpc_server () ?? "";
            if (start.length > 0) dlg.initial_file = File.new_for_path (start);

            try {
                var file = yield dlg.open (app_window, null);
                if (file != null) {
                    string? path = file.get_path ();
                    if (path != null && FileUtils.test (path, FileTest.IS_EXECUTABLE)) {
                        app_window.settings.save_rpc_server_path (path);
                        app_window.settings.save_rpc_server_source (RpcServerSource.CUSTOM);
                        sync_rpc_source_dropdown ();
                        app_window.show_toast ("Chatmail server path saved");
                        app_window.reconnect_rpc_server.begin ();
                    } else {
                        show_error (app_window, "Selected file is not an executable binary.");
                    }
                }
            } catch (Error e) {
                if (!(e is Gtk.DialogError) && !(e is IOError.CANCELLED))
                    show_error (app_window, e.message);
            }
            update_rpc_row ();
        }

        /* One-click: download the latest server into Parla's data dir. */
        private async void install_managed_server () {
            if (!RpcInstaller.can_auto_install ()) {
                /* No prebuilt binary for this arch — fall back to the browser. */
                yield open_rpc_download_page ();
                return;
            }

            rpc_download_btn.sensitive = false;
            string prev_subtitle = rpc_row.subtitle;
            var installer = new RpcInstaller ();
            installer.progress.connect ((received, total) => {
                if (total > 0) {
                    rpc_row.subtitle = "Downloading… %.0f%%".printf (
                        (double) received / (double) total * 100.0);
                } else {
                    rpc_row.subtitle = "Downloading… %.1f MB".printf (
                        received / 1048576.0);
                }
            });

            try {
                yield installer.download_latest ();
                /* Make sure the freshly installed managed binary is the one
                   Parla resolves immediately. */
                if (app_window.settings.rpc_server_source != RpcServerSource.AUTO) {
                    app_window.settings.save_rpc_server_source (RpcServerSource.AUTO);
                    sync_rpc_source_dropdown ();
                }
                app_window.show_toast ("Chatmail server installed");
                yield app_window.reconnect_rpc_server ();
            } catch (Error e) {
                rpc_row.subtitle = prev_subtitle;
                app_window.show_toast ("Download failed: " + e.message);
            } finally {
                rpc_download_btn.sensitive = true;
            }
            update_rpc_row ();
        }

        private async void open_rpc_download_page () {
            try {
                yield (new Gtk.UriLauncher (
                    "https://github.com/chatmail/core/releases/latest")).launch (
                    app_window, null);
            } catch (Error e) {
                show_error (app_window, "Unable to open download page: " + e.message);
            }
        }

        private void on_reset_settings () {
            confirm_action (app_window, "Factory Reset",
                "This will delete all Parla configuration files and close the application. " +
                "Your Delta Chat accounts and messages are not affected.",
                "reset", "Reset & Close", () => {
                    delete_parla_config ();
                    app_window.quit_application ();
                });
        }

        private void apply_background () {
            ((Dc.Application) app_window.application).apply_background (
                app_window.settings.background_mode,
                app_window.settings.background_color);
        }

        private void apply_theme_override () {
            ((Dc.Application) app_window.application).apply_theme_override (
                app_window.settings.theme_override);
        }

        private static void apply_hex_to_button (Gtk.ColorDialogButton btn,
                                                  string hex) {
            var rgba = Gdk.RGBA ();
            if (hex.length == 0 || !rgba.parse (hex)) {
                rgba.parse ("#3584e4");
            }
            btn.set_rgba (rgba);
        }

        private static void delete_parla_config () {
            var dir = Path.build_filename (
                Environment.get_user_config_dir (), "parla");
            FileUtils.unlink (Path.build_filename (dir, "settings.ini"));
            DirUtils.remove (dir);
        }
    }

}
