namespace Dc {

    /**
     * Compact inline player for audio / voice attachments: a single
     * play/stop button plus the file name — no bulky media-controls bar.
     *
     * Playback quirk this works around: a bare Gtk.MediaFile never actually
     * plays (it prepares asynchronously and a manual play() is dropped), and
     * even a realized stream won't start on a manual play() — only a mapped
     * Gtk.Video with autoplay=true reliably drives the GStreamer pipeline,
     * and once paused it won't resume. So the engine is a hidden Gtk.Video
     * (controls removed, opacity 0) created fresh on each play and torn down
     * to stop. pause() does work, which lets us halt cleanly.
     */
    public class AudioPlayer : Gtk.Box {

        private string path;
        private Gtk.Button btn;
        private Gtk.Overlay host;
        private Gtk.Video? engine = null;

        public AudioPlayer (string path, string? name) {
            Object (orientation: Gtk.Orientation.HORIZONTAL, spacing: 8);
            this.path = path;
            add_css_class ("message-audio");
            halign = Gtk.Align.START;

            btn = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            btn.add_css_class ("circular");
            btn.valign = Gtk.Align.CENTER;
            btn.tooltip_text = "Play";
            btn.clicked.connect (toggle);

            /* The hidden Gtk.Video engine lives as an overlay on top of the
               button so it adds no width of its own. */
            host = new Gtk.Overlay ();
            host.child = btn;
            host.valign = Gtk.Align.CENTER;
            append (host);

            var label = new Gtk.Label (
                (name != null && name.length > 0) ? name : "Voice message");
            label.add_css_class ("message-audio-name");
            label.ellipsize = Pango.EllipsizeMode.MIDDLE;
            label.max_width_chars = 22;
            label.xalign = 0;
            label.valign = Gtk.Align.CENTER;
            append (label);
        }

        private void toggle () {
            if (engine != null) stop ();
            else play ();
        }

        private void play () {
            stop ();
            var e = new Gtk.Video ();
            e.autoplay = true;
            e.loop = false;
            e.can_target = false;
            e.opacity = 0;
            e.set_size_request (0, 0);
            e.set_filename (path);
            hide_controls (e);
            host.add_overlay (e);
            engine = e;

            var st = e.get_media_stream ();
            if (st != null) {
                st.notify["playing"].connect (() => {
                    if (engine == null) return;
                    var s = engine.get_media_stream ();
                    /* A play stream only flips to "not playing" when it ends
                       (we pause explicitly via stop()), so reset to idle. */
                    if (s == null || !s.playing) stop ();
                    else set_playing_visuals (true);
                });
            }
            set_playing_visuals (true);
        }

        private void stop () {
            var e = engine;
            engine = null;
            if (e != null) {
                var st = e.get_media_stream ();
                if (st != null) st.pause ();
                host.remove_overlay (e);
            }
            set_playing_visuals (false);
        }

        private void set_playing_visuals (bool playing) {
            btn.icon_name = playing
                ? "media-playback-stop-symbolic"
                : "media-playback-start-symbolic";
            btn.tooltip_text = playing ? "Stop" : "Play";
        }

        /* Remove Gtk.Video's built-in controls so the engine collapses to a
           zero-sized, invisible playback surface. */
        private static void hide_controls (Gtk.Widget w) {
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                if (c is Gtk.MediaControls) c.visible = false;
                hide_controls (c);
            }
        }
    }
}
