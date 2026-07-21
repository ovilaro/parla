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
        private Gtk.CssProvider? font_provider = null;

        public Application () {
            Object (
                application_id: "io.github.trufae.Parla",
                /* HANDLES_COMMAND_LINE (not HANDLES_OPEN) so we see invite URIs
                   verbatim: GFile rewrites "openpgp4fpr:FPR#..." into
                   "openpgp4fpr:///FPR#..." which Delta Chat's check_qr rejects. */
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
        }

        construct {
            rpc = new RpcClient ();
        }

        public void apply_theme_override (ThemeOverride theme) {
            var style = Adw.StyleManager.get_default ();
            switch (theme) {
            case ThemeOverride.LIGHT:
                style.color_scheme = Adw.ColorScheme.FORCE_LIGHT;
                break;
            case ThemeOverride.DARK:
                style.color_scheme = Adw.ColorScheme.FORCE_DARK;
                break;
            case ThemeOverride.SYSTEM:
            default:
                style.color_scheme = Adw.ColorScheme.DEFAULT;
                break;
            }
        }

        public void reset_rpc_client () {
            rpc.stop ();
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

        public void apply_font (string family, FontAttribute attr, int size) {
            var display = Gdk.Display.get_default ();
            if (display == null) return;

            if (font_provider != null) {
                remove_provider_for_display (display, font_provider);
                font_provider = null;
            }

            string clean_family = family.strip ();
            int clean_size = SettingsManager.clamp_font_size (size);
            if (clean_family.length == 0 &&
                attr == FontAttribute.REGULAR &&
                clean_size == FONT_SIZE_SYSTEM) {
                return;
            }

            var css = new StringBuilder (".conversation-view {");
            if (clean_family.length > 0) {
                css.append (" font-family: \"%s\";".printf (
                    css_string (clean_family)));
            }
            css.append (" font-style: %s; font-weight: %s;".printf (
                attr.css_style (), attr.css_weight ()));
            if (clean_size > FONT_SIZE_SYSTEM) {
                css.append (" font-size: %dpt;".printf (clean_size));
            }
            css.append (" }\n");

            font_provider = new Gtk.CssProvider ();
            font_provider.load_from_string (css.str);
            add_provider_for_display (
                display,
                font_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1
            );
        }

        private static string css_string (string value) {
            return value.replace ("\\", "\\\\").replace ("\"", "\\\"");
        }

        protected override void activate () {
            get_or_create_window ().restore_from_tray ();
        }

        private Dc.Window get_or_create_window () {
            foreach (var win in get_windows ()) {
                if (win is Dc.Window) return (Dc.Window) win;
            }
            return new Dc.Window (this);
        }

        /* The app is single-instance and registered as the handler for
           "openpgp4fpr:" links (see the .desktop file). When the OS — or a
           second `parla <uri>` invocation — hands us a URI, it arrives here on
           the primary instance. We pass the raw argument straight through so
           the SecureJoin code receives the exact link the user clicked. */
        protected override int command_line (ApplicationCommandLine cmd) {
            var window = get_or_create_window ();
            window.restore_from_tray ();

            foreach (unowned string arg in cmd.get_arguments ()) {
                if (is_delta_invite_uri (arg)) {
                    window.handle_invite_uri (arg);
                    break;
                }
            }
            return 0;
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
            apply_theme_override (settings.theme_override);
            apply_accent_color (settings.accent_color);
            apply_background (settings.background_mode, settings.background_color);
            apply_font (
                settings.font_family,
                settings.font_attribute,
                settings.font_size);
            register_icons ();
            Gtk.Window.set_default_icon_name ("io.github.trufae.Parla");

            /* Clicking an unread notification activates this action with the
               account and, when there is a single fresh message, the chat it
               belongs to. */
            var open_chat = new SimpleAction (
                "open-chat", new VariantType ("(ii)"));
            open_chat.activate.connect ((param) => {
                if (param == null) return;
                int acct_id = 0, chat_id = 0;
                param.get ("(ii)", out acct_id, out chat_id);
                var window = get_or_create_window ();
                window.restore_from_tray ();
                window.open_chat_from_notification.begin (acct_id, chat_id);
            });
            add_action (open_chat);

            var primary = Platform.primary_accelerator_prefix ();
            set_accels_for_action ("win.new-chat", { primary + "n" });
            set_accels_for_action ("win.refresh", { primary + "r" });
            set_accels_for_action ("win.settings", { primary + "comma" });
            set_accels_for_action ("win.quit", { primary + "q" });
            set_accels_for_action ("win.font-increase",
                { primary + "plus", primary + "equal", primary + "KP_Add" });
            set_accels_for_action ("win.font-decrease",
                { primary + "minus", primary + "KP_Subtract" });
            set_accels_for_action ("win.font-reset",
                { primary + "0", primary + "KP_0" });
        }

        private void register_icons () {
            var theme = Gtk.IconTheme.get_for_display (Gdk.Display.get_default ());
            /* App-bundled icons (e.g. "parla-welcome") are embedded in the
               binary as a GResource so they resolve regardless of install
               prefix, XDG_DATA_DIRS, or a stale hicolor icon cache. */
            theme.add_resource_path ("/io/github/trufae/Parla/icons");
            /* Support running uninstalled: add the project data/icons dir */
            string? exe_path = Platform.get_executable_path ();
            if (exe_path != null) {
                var exe_dir = File.new_for_path (exe_path).get_parent ();
                /* exe in builddir/ → icons in ../data/icons */
                var project_icons = exe_dir.get_parent ().get_child ("data").get_child ("icons");
                if (project_icons.query_exists ()) {
                    theme.add_search_path (project_icons.get_path ());
                }
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
            .message-avatar {
                margin-bottom: 1px;
            }
            .presence-avatar-ring {
                padding: 2px;
                border-radius: 9999px;
                border: 2px solid #2ec27e;
                background-color: alpha(#2ec27e, 0.16);
                box-shadow:
                    0 0 0 2px alpha(#2ec27e, 0.14),
                    0 0 10px alpha(#2ec27e, 0.48);
            }
            .presence-avatar-ring-small {
                padding: 1px;
                border-width: 1px;
                box-shadow:
                    0 0 0 1px alpha(#2ec27e, 0.18),
                    0 0 8px alpha(#2ec27e, 0.52);
            }
            .list-presence-avatar-ring {
                margin-left: -4px;
            }
            .message-sender {
                font-weight: bold;
                font-size: small;
                color: @view_fg_color;
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
            .message-edited {
                font-size: x-small;
                font-style: italic;
                opacity: 0.55;
                margin-top: 2px;
            }
            .message-big-emoji {
                font-size: 500%;
            }
            .message-medium-emoji {
                font-size: 300%;
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
            .message-workspace {
                padding: 3px 6px;
                border-radius: 6px;
            }
            .message-workspace:hover {
                background-color: alpha(@view_fg_color, 0.06);
            }
            .message-workspace .message-sender {
                font-size: inherit;
            }
            .message-workspace .message-time {
                margin-top: 0;
            }
            /* Quick actions floated over a hovered Workspace row. Kept
               compact so the bar fits even a grouped one-line row. */
            .message-actions-bar {
                padding: 0 1px;
                border-radius: 8px;
                background-color: @view_bg_color;
                box-shadow: 0 1px 4px alpha(black, 0.3);
            }
            .message-actions-bar > button {
                min-width: 20px;
                min-height: 20px;
                padding: 2px 5px;
            }
            .message-attachment { padding: 4px 0; }
            .message-full-text-button {
                font-size: small;
                padding: 2px 0;
            }
            .message-full-text-status {
                font-size: small;
                opacity: 0.65;
            }
            .markdown-table {
                margin-top: 4px;
                margin-bottom: 4px;
                border-radius: 6px;
                background-color: alpha(@view_fg_color, 0.04);
            }
            .markdown-table-cell {
                padding: 4px 6px;
                border-bottom: 1px solid alpha(@view_fg_color, 0.12);
                border-right: 1px solid alpha(@view_fg_color, 0.10);
            }
            .markdown-table-header {
                font-weight: bold;
                background-color: alpha(@view_fg_color, 0.06);
            }
            .markdown-task-line {
                margin-top: 1px;
                margin-bottom: 1px;
            }
            .markdown-task-toggle {
                min-width: 20px;
                min-height: 20px;
                padding: 0;
                margin: 0;
                font-size: inherit;
            }
            .markdown-task-glyph {
                min-width: 20px;
                opacity: 0.9;
            }
            .message-image { border-radius: 12px; margin-top: 4px; }
            .message-sticker { margin-top: 4px; }
            .message-bubble.sticker.incoming,
            .message-bubble.sticker.outgoing {
                background-color: transparent;
                padding: 4px 0;
            }
            .message-video-frame {
                border-radius: 12px;
                margin-top: 4px;
                background-color: alpha(black, 0.72);
            }
            .message-video-bg {
                background-color: alpha(black, 0.72);
            }
            .message-video-play {
                min-width: 36px;
                min-height: 36px;
                border-radius: 9999px;
                background-color: alpha(black, 0.48);
                color: white;
            }
            .message-video-name {
                color: white;
                font-size: small;
                padding: 2px 6px;
                border-radius: 6px;
                background-color: alpha(black, 0.45);
                text-shadow: 0 1px alpha(black, 0.55);
            }
            .image-viewer-overlay {
                background-color: alpha(black, 0.75);
            }
            .compose-bar { border-top: none; }
            .selection-action-bar {
                padding: 4px 8px;
            }
            .compose-entry {
                border-radius: 18px;
                transition: background-color 120ms ease-out, box-shadow 120ms ease-out;
            }
            .compose-entry-active {
                background-color: alpha(@accent_bg_color, 0.10);
                box-shadow: inset 0 0 0 2px alpha(@accent_bg_color, 0.70);
            }
            .attachment-bar {
                padding: 6px 10px;
                margin-bottom: 6px;
                border-left: 3px solid @accent_bg_color;
                background-color: alpha(@view_fg_color, 0.05);
                border-radius: 4px;
                min-height: 56px;
            }
            .attachment-preview-image {
                border-radius: 6px;
                background-color: alpha(@view_fg_color, 0.08);
            }
            .attachment-preview-icon {
                color: @accent_color;
            }
            .attachment-preview-name {
                font-weight: bold;
            }
            .attachment-preview-meta {
                font-size: x-small;
                opacity: 0.65;
            }
            .chat-drop-active {
                background-color: alpha(@accent_bg_color, 0.08);
                box-shadow: inset 0 0 0 2px alpha(@accent_bg_color, 0.45);
            }
            .chat-row { border-radius: 8px; padding: 4px; }
            .chat-row-mention {
                background-color: alpha(@accent_bg_color, 0.16);
            }
            .mention-marker {
                color: @accent_bg_color;
                font-weight: bold;
            }
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
            .contact-request-bar {
                padding: 4px 8px;
            }
            .message-select-check {
                margin-left: 2px;
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
                font-size: 0.85em;
                font-weight: bold;
                color: @accent_color;
            }
            .quote-text {
                font-size: 0.85em;
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
                font-size: 0.85em;
                opacity: 0.8;
            }
            .compose-entry-scroll scrollbar slider {
                min-height: 16px;
            }
            .long-message-bar {
                padding: 4px 8px;
                margin-bottom: 4px;
                border-left: 3px solid @warning_bg_color;
                background-color: alpha(@warning_bg_color, 0.12);
                border-radius: 4px;
            }
            .long-message-label {
                font-size: 0.85em;
                opacity: 0.8;
            }
            .pinned-bar {
                background-color: alpha(@accent_bg_color, 0.08);
                border-bottom: 1px solid alpha(@view_fg_color, 0.12);
            }
            .conversation-media-bar {
                background-color: alpha(@accent_bg_color, 0.14);
                border-bottom: 1px solid alpha(@view_fg_color, 0.16);
            }
            .conversation-media-sender {
                font-weight: bold;
                font-size: small;
            }
            .conversation-media-sent {
                font-size: x-small;
                opacity: 0.62;
            }
            .conversation-media-time {
                font-family: monospace;
                font-size: small;
                opacity: 0.78;
            }
            scale.conversation-media-progress {
                padding: 0;
                margin: 0;
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
            }
            .message-tick-failed {
                font-size: small;
                color: @error_color;
                opacity: 1;
                margin-left: 2px;
            }
            .message-pin {
                font-size: small;
                margin-left: 2px;
            }
            .reaction-bar {
                margin-top: 2px;
            }
            button.reaction-badge {
                min-height: 22px;
                min-width: 0;
                padding: 1px 8px;
                border-radius: 9999px;
                background-color: alpha(@view_fg_color, 0.10);
                color: @view_fg_color;
            }
            button.reaction-badge:hover {
                background-color: alpha(@accent_bg_color, 0.22);
            }
            .reaction-users-pill {
                padding: 7px 10px;
                border-radius: 18px;
                background-color: alpha(@view_fg_color, 0.88);
                color: @view_bg_color;
                box-shadow: 0 2px 8px alpha(@view_fg_color, 0.25);
            }
            .reaction-user-row {
                min-height: 24px;
            }
            .reaction-user-name {
                font-size: small;
            }
            .message-details-sender {
                padding: 8px;
                border-radius: 8px;
            }
            .message-details-edit-view {
                background-color: alpha(@view_fg_color, 0.04);
                border-radius: 8px;
            }
            .message-details-reaction-emoji {
                font-size: 1.4em;
                min-width: 36px;
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
            /* Floating "Loading…" pill shown while older messages are
               fetched from the JSON-RPC server. */
            .loading-pill {
                padding: 5px 14px;
                border-radius: 16px;
                opacity: 0.95;
            }
            /* Destructive entry in a flat popover menu. Uses the red text
               color (not @destructive_fg_color, which is white and meant for
               a solid red button — on a flat item that leaves white text). */
            .menu-destructive {
                color: @destructive_color;
            }
        """;
    }
}
