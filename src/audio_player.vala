namespace Dc {

    /**
     * Compact inline player for audio / voice attachments: a single
     * play/stop button plus the file name.
     *
     * On Linux, GTK4's gstreamer media backend drives Gtk.MediaFile fine.
     * macOS brew's gtk4 ships without a media backend, so MediaFile is a
     * silent no-op there — we shell out to afplay instead. The same
     * shell-out path is also available on Linux via gst-play-1.0/mpv/
     * ffplay, opt-in through the "System audio player" setting.
     */
    public class AudioPlayer : Gtk.Box {

        /* Set by SettingsManager. When true, prefer the external player even
           when the GTK media backend is available. */
        public static bool prefer_system = false;

        private string path;
        private Gtk.Button btn;
        private Gtk.MediaFile? media = null;
        private GLib.Subprocess? proc = null;
        private Posix.pid_t proc_pid = 0;
        private GLib.Cancellable? proc_cancel = null;

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
            append (btn);

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
            if (media != null || proc != null) stop ();
            else play ();
        }

        private void play () {
            stop ();
            /* macOS has no usable GTK media backend in brew's gtk4, so the
               external path is mandatory there regardless of the setting. */
            bool try_external = prefer_system || Platform.is_macos ();
            if (try_external) {
                var argv = find_external_command ();
                if (argv != null && play_external (argv)) {
                    set_playing_visuals (true);
                    return;
                }
            }
            play_media ();
            set_playing_visuals (true);
        }

        private string[]? find_external_command () {
            if (Environment.find_program_in_path ("afplay") != null)
                return {"afplay", path};
            if (Environment.find_program_in_path ("gst-play-1.0") != null)
                return {"gst-play-1.0", "--quiet", path};
            if (Environment.find_program_in_path ("mpv") != null)
                return {"mpv", "--no-video", "--really-quiet", path};
            if (Environment.find_program_in_path ("ffplay") != null)
                return {"ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path};
            return null;
        }

        private bool play_external (string[] argv) {
            try {
                var launcher = new GLib.SubprocessLauncher (
                    SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                var p = launcher.spawnv (argv);
                proc = p;
                var pid_str = p.get_identifier ();
                proc_pid = pid_str != null ? (Posix.pid_t) int.parse (pid_str) : 0;
                proc_cancel = new GLib.Cancellable ();
                p.wait_async.begin (proc_cancel, (obj, res) => {
                    try { p.wait_async.end (res); } catch (Error e) { /* cancelled */ }
                    if (proc == p) stop ();
                });
                return true;
            } catch (Error e) {
                warning ("audio: failed to spawn %s: %s", argv[0], e.message);
                return false;
            }
        }

        private void play_media () {
            var m = Gtk.MediaFile.for_filename (path);
            media = m;
            m.notify["ended"].connect (() => {
                if (media == m && m.ended) stop ();
            });
            m.notify["error"].connect (() => {
                if (media == m && m.error != null) stop ();
            });
            m.play_now ();
        }

        private void stop () {
            if (proc_pid > 0) {
                /* Posix.kill directly because g_subprocess_force_exit can be
                   a no-op in some bundled-on-macOS scenarios; SIGTERM first so
                   children clean up, SIGKILL as backstop. */
                Posix.kill (proc_pid, Posix.Signal.TERM);
                Posix.kill (proc_pid, Posix.Signal.KILL);
                proc_pid = 0;
            }
            if (proc != null) {
                proc = null;
            }
            if (proc_cancel != null) {
                proc_cancel.cancel ();
                proc_cancel = null;
            }
            if (media != null) {
                media.pause ();
                media = null;
            }
            set_playing_visuals (false);
        }

        private void set_playing_visuals (bool playing) {
            btn.icon_name = playing
                ? "media-playback-stop-symbolic"
                : "media-playback-start-symbolic";
            btn.tooltip_text = playing ? "Stop" : "Play";
        }
    }
}
