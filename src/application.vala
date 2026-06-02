namespace Dc {

    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    private extern void add_provider_for_display (
        Gdk.Display display,
        Gtk.StyleProvider provider,
        uint priority
    );

    [CCode (cname = "gtk_style_context_remove_provider_for_display")]
    private extern void remove_provider_for_display (
        Gdk.Display display,
        Gtk.StyleProvider provider
    );

    public class Application : Adw.Application {

        public RpcClient rpc { get; private set; }

        private Gtk.CssProvider? accent_provider = null;
        private Gtk.CssProvider? background_provider = null;

        public Application () {
            Object (
                application_id: "io.github.trufae.Parla",
                flags: ApplicationFlags.FLAGS_NONE
            );
        }

        construct {
            rpc = new RpcClient ();
        }

        public void apply_accent_color (string hex) {
            var display = Gdk.Display.get_default ();
            if (display == null) return;

            if (accent_provider != null) {
                remove_provider_for_display (display, accent_provider);
                accent_provider = null;
            }
            if (hex.length == 0) return;

            var rgba = Gdk.RGBA ();
            if (!rgba.parse (hex)) return;

            /* Pick a readable foreground based on luminance */
            double y = 0.299 * rgba.red + 0.587 * rgba.green + 0.114 * rgba.blue;
            string fg = y > 0.6 ? "rgb(0,0,0)" : "rgb(255,255,255)";

            string css =
                "@define-color accent_bg_color " + hex + ";\n" +
                "@define-color accent_color " + hex + ";\n" +
                "@define-color accent_fg_color " + fg + ";\n" +
                /* Legacy GTK names — used by plain (non-libadwaita) widgets
                   such as selections and some controls that would otherwise
                   keep the default blue. */
                "@define-color theme_selected_bg_color " + hex + ";\n" +
                "@define-color theme_selected_fg_color " + fg + ";\n";

            accent_provider = new Gtk.CssProvider ();
            accent_provider.load_from_string (css);
            add_provider_for_display (
                display,
                accent_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
            );
        }

        /* Recolor the main window background. The rule is scoped to the
           ".parla-custom-bg" class (added to the window) so dialogs and
           popovers keep the theme background. The color shows through the
           window's transparent surfaces — the conversation backdrop (behind
           the message cards and around them) and the welcome status page.
           Opaque chrome (the header bars and the navigation sidebar) keeps
           its own theme shade and is unaffected. */
        public void apply_background (BackgroundMode mode, string hex) {
            var display = Gdk.Display.get_default ();
            if (display == null) return;

            if (background_provider != null) {
                remove_provider_for_display (display, background_provider);
                background_provider = null;
            }
            if (mode == BackgroundMode.SYSTEM) return;

            /* Fall back to the same default the picker shows when no color
               has been chosen yet, so the window matches the button. */
            string color = hex.length > 0 ? hex : "#3584e4";
            var rgba = Gdk.RGBA ();
            if (!rgba.parse (color)) return;

            string rule;
            if (mode == BackgroundMode.GRADIENT) {
                /* Fade from the chosen color at the top into the theme's
                   default window background, so the bottom always matches
                   the system color. */
                rule = "background-image: linear-gradient(to bottom, "
                    + color + ", @window_bg_color);";
            } else {
                rule = "background-color: " + color + ";"
                    + " background-image: none;";
            }

            /* The conversation list paints an opaque view background that
               would otherwise hide the custom color in every open chat.
               Make it transparent here — scoped to ".conversation-view" so
               the sidebar, settings lists and dialogs keep their theme
               background — so the chosen color shows behind the messages.
               These rules live in this provider (not the static sheet) so
               they vanish together with the override in System mode. */
            string css = "window.parla-custom-bg { " + rule + " }\n"
                + "window.parla-custom-bg .conversation-view scrolledwindow,\n"
                + "window.parla-custom-bg .conversation-view listview {"
                + " background-color: transparent; background-image: none; }\n";

            background_provider = new Gtk.CssProvider ();
            background_provider.load_from_string (css);
            add_provider_for_display (
                display,
                background_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
            );
        }

        protected override void activate () {
            Dc.Window? window = null;
            foreach (var win in get_windows ()) {
                if (win is Dc.Window) {
                    window = (Dc.Window) win;
                    break;
                }
            }
            if (window == null) {
                window = new Dc.Window (this);
            }
            window.restore_from_tray ();
        }

        protected override void startup () {
            base.startup ();
            load_css ();
            /* Apply the saved accent override before any window/widget is
               built, so named colors resolve to it from the first style
               computation. Applying it later (in Window.construct, after
               build_ui) leaves already-styled widgets blue until a re-apply. */
            var settings = new SettingsManager ();
            settings.load ();
            apply_accent_color (settings.accent_color);
            apply_background (settings.background_mode, settings.background_color);
            register_icons ();
            Gtk.Window.set_default_icon_name ("io.github.trufae.Parla");

            set_accels_for_action ("win.new-chat", {"<Control>n"});
            set_accels_for_action ("win.refresh", {"<Control>r"});
            set_accels_for_action ("win.settings", {"<Control>comma"});
            set_accels_for_action ("win.quit", {"<Control>q"});
        }

        private void register_icons () {
            var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            /* App-bundled icons (e.g. "parla-welcome") are embedded in the
               binary as a GResource so they resolve regardless of install
               prefix, XDG_DATA_DIRS, or a stale hicolor icon cache. */
            theme.add_resource_path ("/io/github/trufae/Parla/icons");
            /* Support running uninstalled: add the project data/icons dir */
            try {
                var exe_path = FileUtils.read_link ("/proc/self/exe");
                var exe_dir = File.new_for_path (exe_path).get_parent ();
                /* exe in builddir/ → icons in ../data/icons */
                var project_icons = exe_dir.get_parent ().get_child ("data").get_child ("icons");
                if (project_icons.query_exists ()) {
                    theme.add_search_path (project_icons.get_path ());
                }
            } catch (FileError e) {
                /* not on Linux or unreadable — fall through to installed path */
            }
        }

        private void load_css () {
            var provider = new Gtk.CssProvider ();
            provider.load_from_string (CSS);
            add_provider_for_display (
                Gdk.Display.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        }

        private const string CSS = """
            .message-bubble {
                padding: 8px 12px;
                border-radius: 16px;
                min-width: 60px;
            }
            .message-bubble.incoming {
                background-color: alpha(@view_fg_color, 0.08);
                border-top-left-radius: 4px;
            }
            .message-bubble.outgoing {
                background-color: alpha(@accent_bg_color, 0.5);
                border-bottom-right-radius: 4px;
            }
            .message-sender {
                font-weight: bold;
                font-size: small;
                color: @accent_color;
            }
            .message-time {
                font-size: x-small;
                opacity: 0.55;
                margin-top: 2px;
            }
            .message-forwarded {
                font-size: small;
                font-style: italic;
                opacity: 0.7;
            }
            .message-irc {
                padding: 1px 0;
            }
            .message-irc .message-sender {
                font-weight: bold;
                font-size: inherit;
            }
            .message-irc .message-sender-other {
                color: @accent_color;
            }
            .message-irc .message-sender-self {
                color: @view_fg_color;
            }
            .message-irc .irc-time {
                font-size: x-small;
                opacity: 0.55;
                margin-top: 0;
                min-width: 40px;
            }
            .message-image-irc {
                border-radius: 8px;
                margin-top: 2px;
                margin-bottom: 2px;
            }
            .message-attachment { padding: 4px 0; }
            .message-image { border-radius: 12px; margin-top: 4px; }
            .image-viewer-overlay {
                background-color: alpha(black, 0.75);
            }
            .compose-bar { border-top: none; }
            .compose-entry { min-height: 36px; border-radius: 18px; }
            .chat-drop-active {
                background-color: alpha(@accent_bg_color, 0.08);
                box-shadow: inset 0 0 0 2px alpha(@accent_bg_color, 0.45);
            }
            .chat-row { border-radius: 8px; padding: 4px; }
            .chat-row-compact {
                margin-left: 0;
                margin-right: 0;
                padding: 2px;
            }
            .sidebar-compact .chat-row {
                margin-left: 0;
                margin-right: 0;
            }
            .compact-unread-badge {
                background-color: @accent_bg_color;
                color: @accent_fg_color;
                border-radius: 9px;
                padding: 0 5px;
                min-width: 16px;
                min-height: 16px;
                font-size: 9pt;
                font-weight: bold;
                margin-top: -2px;
                margin-right: -4px;
                box-shadow: 0 0 0 2px @view_bg_color;
            }
            .compact-unread-badge-muted {
                background-color: alpha(@view_fg_color, 0.55);
                color: @view_bg_color;
                border-radius: 9px;
                padding: 0 5px;
                min-width: 16px;
                min-height: 16px;
                font-size: 9pt;
                font-weight: bold;
                margin-top: -2px;
                margin-right: -4px;
                box-shadow: 0 0 0 2px @view_bg_color;
            }
            .compact-request-marker {
                background-color: @warning_color;
                color: @view_bg_color;
                border-radius: 9px;
                padding: 0 5px;
                min-width: 16px;
                min-height: 16px;
                font-size: 9pt;
                font-weight: bold;
                margin-top: -2px;
                margin-right: -4px;
                box-shadow: 0 0 0 2px @view_bg_color;
            }
            .compact-pin-marker {
                background-color: @view_bg_color;
                color: alpha(@view_fg_color, 0.7);
                border-radius: 8px;
                padding: 1px;
                margin-bottom: -2px;
                margin-right: -2px;
                box-shadow: 0 0 0 1px alpha(@view_fg_color, 0.15);
            }
            .current-account-row {
                background-color: alpha(@accent_bg_color, 0.10);
                border-radius: 8px;
            }
            .account-unread-dot {
                background-color: @error_bg_color;
                border-radius: 9999px;
                min-width: 14px;
                min-height: 14px;
                margin-bottom: -2px;
                margin-right: -2px;
                box-shadow: 0 0 0 2px @headerbar_bg_color;
            }
            .account-unread-badge {
                background-color: @error_bg_color;
                color: @error_fg_color;
                border-radius: 9px;
                padding: 0 4px;
                min-width: 16px;
                min-height: 16px;
                font-size: 8pt;
                font-weight: bold;
                margin-bottom: -3px;
                margin-right: -3px;
                box-shadow: 0 0 0 2px @view_bg_color;
            }
            .unread-dot {
                color: @accent_bg_color;
                font-size: 12px;
            }
            .unread-dot-muted {
                color: alpha(@view_fg_color, 0.4);
                font-size: 12px;
            }
            .unread-name {
                font-weight: 800;
            }
            .unread-badge {
                background-color: @accent_bg_color;
                color: @accent_fg_color;
                border-radius: 10px;
                padding: 0 6px;
                min-width: 20px; min-height: 20px;
                font-size: small; font-weight: bold;
            }
            .unread-badge-muted {
                background-color: alpha(@view_fg_color, 0.35);
                color: @view_bg_color;
                border-radius: 10px;
                padding: 0 6px;
                min-width: 20px; min-height: 20px;
                font-size: small; font-weight: bold;
            }
            .contact-request-badge {
                background-color: @warning_bg_color;
                color: @warning_fg_color;
                border-radius: 10px;
                padding: 0 6px;
                min-width: 20px; min-height: 20px;
                font-size: small; font-weight: bold;
            }
            .message-new {
                background-color: alpha(@accent_bg_color, 0.15);
                transition: background-color 2s ease-out;
            }
            .quote-block {
                border-left: 3px solid @accent_bg_color;
                padding: 4px 8px;
                margin-bottom: 4px;
                background-color: alpha(@view_fg_color, 0.05);
                border-radius: 4px;
            }
            .quote-sender {
                font-size: small;
                font-weight: bold;
                color: @accent_color;
            }
            .quote-text {
                font-size: small;
                opacity: 0.75;
            }
            .reply-bar {
                padding: 4px 8px;
                margin-bottom: 4px;
                border-left: 3px solid @accent_bg_color;
                background-color: alpha(@view_fg_color, 0.05);
                border-radius: 4px;
            }
            .reply-label {
                font-size: small;
                opacity: 0.8;
            }
            .pinned-bar {
                background-color: alpha(@accent_bg_color, 0.08);
                border-bottom: 1px solid alpha(@view_fg_color, 0.12);
            }
            /* Delivery / read ticks next to the timestamp. */
            .message-tick {
                font-size: small;
                opacity: 0.60;
                margin-left: 2px;
                letter-spacing: -3px;
            }
            .message-tick-read {
                font-size: small;
                color: @success_color;
                opacity: 1;
                margin-left: 2px;
                letter-spacing: -3px;
            }
            .message-tick-failed {
                font-size: small;
                color: @error_color;
                opacity: 1;
                margin-left: 2px;
            }
            /* Floating "disconnected" pill over the chat area. */
            .connection-banner {
                background-color: alpha(@view_fg_color, 0.80);
                color: @view_bg_color;
                padding: 6px 14px;
                border-radius: 18px;
                box-shadow: 0 2px 8px alpha(@view_fg_color, 0.25);
            }
            .connection-banner-label {
                font-size: small;
            }
        """;
    }
}
