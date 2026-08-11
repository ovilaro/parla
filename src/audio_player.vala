namespace Dc {

    /** Immutable metadata needed to render and locate the active voice note. */
    public class AudioPlaybackItem : Object {
        public int account_id { get; construct; }
        public int chat_id { get; construct; }
        public int message_id { get; construct; }
        public string path { get; construct; }
        public string sender_name { get; construct; }
        public string? sender_address { get; construct; }
        public string? avatar_path { get; construct; }
        public int64 sent_timestamp { get; construct; }

        public AudioPlaybackItem (Message msg, int account_id) {
            Object (
                account_id: account_id,
                chat_id: msg.chat_id,
                message_id: msg.id,
                path: msg.file_path,
                sender_name: MessageRow.effective_sender_name (msg),
                sender_address: msg.sender_address,
                avatar_path: msg.is_outgoing
                    ? MessageRow.self_avatar_path : msg.sender_avatar_path,
                sent_timestamp: msg.timestamp
            );
        }
    }

    /**
     * Application-wide voice-message playback session. Inline players and the
     * conversation media bar both control this object, so row recycling does
     * not interrupt playback or lose the current position.
     */
    public class AudioPlayback : Object {

        private static AudioPlayback? instance = null;

        public AudioPlaybackItem? current_item { get; private set; default = null; }
        public int current_message_id { get; private set; default = 0; }
        public bool playing { get; private set; default = false; }
        public bool can_seek { get; private set; default = false; }
        public bool external_backend { get; private set; default = false; }
        public bool has_previous { get; private set; default = false; }
        public bool has_next { get; private set; default = false; }
        public int64 position_us { get; private set; default = 0; }
        public int64 duration_us { get; private set; default = 0; }

        private string? path = null;
        private Gtk.MediaFile? media = null;
        private GLib.Subprocess? proc = null;
        private Posix.pid_t proc_pid = 0;
        private GLib.Cancellable? proc_cancel = null;
        private uint progress_timer = 0;
        private int64 external_started_us = 0;
        private int64 external_elapsed_us = 0;
        private bool external_paused = false;

        public signal void finished (int message_id);

        public static AudioPlayback shared () {
            if (instance == null) instance = new AudioPlayback ();
            return instance;
        }

        public void play_message (Message msg, int account_id) {
            if (msg.id <= 0 || !msg.has_local_file || !msg.is_audio_file ()) return;
            var item = new AudioPlaybackItem (msg, account_id);
            stop_backend ();
            path = item.path;
            position_us = 0;
            duration_us = 0;
            can_seek = false;
            external_backend = false;
            has_previous = false;
            has_next = false;
            current_item = item;
            current_message_id = item.message_id;
            start_backend ();
        }

        public void set_navigation (bool previous, bool next) {
            has_previous = previous;
            has_next = next;
        }

        public void toggle () {
            if (current_message_id <= 0 || path == null) return;
            if (playing) pause ();
            else resume ();
        }

        public void stop () {
            stop_backend ();
            path = null;
            position_us = 0;
            duration_us = 0;
            has_previous = false;
            has_next = false;
            current_item = null;
            current_message_id = 0;
        }

        public void seek_fraction (double fraction) {
            if (media == null || !can_seek || duration_us <= 0) return;
            double clamped = double.max (0.0, double.min (1.0, fraction));
            int64 target = (int64) (clamped * duration_us);
            media.seek (target);
            position_us = target;
        }

        private void pause () {
            if (media != null) {
                media.pause ();
                sync_media_state (media);
                playing = false;
                stop_progress_timer ();
                return;
            }

            /* POSIX external players can be suspended without losing their
               position. Windows has no equivalent signal, so it restarts. */
#if WINDOWS
            stop_external ();
            position_us = 0;
#else
            if (proc_pid > 0) {
                update_external_position ();
                Posix.kill (proc_pid, Posix.Signal.STOP);
                external_elapsed_us = position_us;
                external_started_us = 0;
                external_paused = true;
            } else {
                stop_external ();
                position_us = 0;
            }
#endif
            playing = false;
            stop_progress_timer ();
        }

        private void resume () {
            if (media != null) {
                media.play_now ();
                playing = true;
                ensure_progress_timer ();
                return;
            }
            if (proc != null && external_paused) {
#if WINDOWS
                stop_external ();
#else
                Posix.kill (proc_pid, Posix.Signal.CONT);
                external_started_us = GLib.get_monotonic_time ();
                external_paused = false;
                playing = true;
                ensure_progress_timer ();
                return;
#endif
            }
            position_us = 0;
            start_backend ();
        }

        private void start_backend () {
            if (path == null) return;
            bool try_external = AudioPlayer.prefer_system || Platform.is_macos ();
            if (try_external) {
                var argv = find_external_command (path);
                if (argv != null && play_external (argv)) {
                    external_backend = true;
                    playing = true;
                    can_seek = false;
                    external_elapsed_us = 0;
                    external_started_us = GLib.get_monotonic_time ();
                    external_paused = false;
                    ensure_progress_timer ();
                    return;
                }
            }
            external_backend = false;
            play_media (path);
            playing = true;
            ensure_progress_timer ();
        }

        private string[]? find_external_command (string file_path) {
            if (Environment.find_program_in_path ("afplay") != null)
                return {"afplay", file_path};
            if (Environment.find_program_in_path ("gst-play-1.0") != null)
                return {"gst-play-1.0", "--quiet", file_path};
            if (Environment.find_program_in_path ("mpv") != null)
                return {"mpv", "--no-video", "--really-quiet", file_path};
            if (Environment.find_program_in_path ("ffplay") != null)
                return {"ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet",
                        file_path};
            return null;
        }

        private bool play_external (string[] argv) {
            try {
                var launcher = new GLib.SubprocessLauncher (
                    SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                var p = SubprocessUtil.spawnv (launcher, argv);
                int played_id = current_message_id;
                proc = p;
                var pid_str = p.get_identifier ();
                proc_pid = pid_str != null
                    ? (Posix.pid_t) int.parse (pid_str) : 0;
                proc_cancel = new GLib.Cancellable ();
                p.wait_async.begin (proc_cancel, (obj, res) => {
                    bool completed = false;
                    try {
                        p.wait_async.end (res);
                        completed = p.get_successful ();
                    } catch (Error e) { /* cancelled */ }
                    if (proc == p) {
                        proc = null;
                        proc_pid = 0;
                        proc_cancel = null;
                        stop_progress_timer ();
                        playing = false;
                        if (completed && current_message_id == played_id)
                            finished (played_id);
                    }
                });
                return true;
            } catch (Error e) {
                warning ("audio: failed to spawn %s: %s", argv[0], e.message);
                return false;
            }
        }

        private void play_media (string file_path) {
            var m = Gtk.MediaFile.for_filename (file_path);
            int played_id = current_message_id;
            media = m;
            m.notify["timestamp"].connect (() => {
                if (media == m) sync_media_state (m);
            });
            m.notify["duration"].connect (() => {
                if (media == m) sync_media_state (m);
            });
            m.notify["seekable"].connect (() => {
                if (media == m) sync_media_state (m);
            });
            m.notify["playing"].connect (() => {
                if (media == m) sync_media_state (m);
            });
            m.notify["ended"].connect (() => {
                if (media == m && m.ended) {
                    sync_media_state (m);
                    playing = false;
                    stop_progress_timer ();
                    if (current_message_id == played_id) finished (played_id);
                }
            });
            m.notify["error"].connect (() => {
                if (media == m && m.error != null) stop_backend ();
            });
            m.play_now ();
            sync_media_state (m);
        }

        private void sync_media_state (Gtk.MediaFile m) {
            position_us = int64.max (0, m.timestamp);
            duration_us = int64.max (0, m.duration);
            can_seek = m.seekable && duration_us > 0;
            playing = m.playing && !m.ended;
        }

        private void ensure_progress_timer () {
            if (progress_timer != 0) return;
            progress_timer = Timeout.add (250, () => {
                if (!playing) {
                    progress_timer = 0;
                    return Source.REMOVE;
                }
                if (media != null) {
                    sync_media_state (media);
                } else if (proc != null && external_started_us > 0) {
                    update_external_position ();
                }
                return Source.CONTINUE;
            });
        }

        private void stop_progress_timer () {
            if (progress_timer == 0) return;
            Source.remove (progress_timer);
            progress_timer = 0;
        }

        private void stop_backend () {
            stop_progress_timer ();
            stop_external ();
            if (media != null) {
                media.pause ();
                media = null;
            }
            playing = false;
            can_seek = false;
            external_backend = false;
        }

        private void update_external_position () {
            if (external_started_us <= 0) return;
            position_us = external_elapsed_us
                + GLib.get_monotonic_time () - external_started_us;
        }

        private void stop_external () {
#if WINDOWS
            var old_proc = proc;
#endif
            proc = null;
            if (proc_pid > 0) {
#if WINDOWS
                if (old_proc != null) old_proc.force_exit ();
#else
                Posix.kill (proc_pid, Posix.Signal.TERM);
                Posix.kill (proc_pid, Posix.Signal.KILL);
#endif
                proc_pid = 0;
            }
            if (proc_cancel != null) {
                proc_cancel.cancel ();
                proc_cancel = null;
            }
            external_started_us = 0;
            external_elapsed_us = 0;
            external_paused = false;
        }
    }

    /** Compact inline control for an audio attachment. */
    public class AudioPlayer : Gtk.Box {

        public static bool prefer_system = false;

        private Message message;
        private int account_id;
        private Gtk.Button btn;
        private Gtk.Button? transcribe_btn = null;
        private Gtk.Label transcription_label;
        private AudioPlayback playback;
        private Transcriber transcriber;
        private ulong current_handler = 0;
        private ulong playing_handler = 0;
        private ulong transcriber_handler = 0;

        public AudioPlayer (Message message, int account_id) {
            Object (orientation: Gtk.Orientation.VERTICAL, spacing: 2);
            this.message = message;
            this.account_id = account_id;
            playback = AudioPlayback.shared ();
            transcriber = Transcriber.shared ();
            add_css_class ("message-audio");
            halign = Gtk.Align.START;

            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);

            btn = new Gtk.Button.from_icon_name ("media-playback-start-symbolic");
            btn.add_css_class ("circular");
            btn.valign = Gtk.Align.CENTER;
            btn.clicked.connect (() => {
                if (is_current_message ()) playback.toggle ();
                else playback.play_message (message, account_id);
            });
            row.append (btn);

            /* No filename on purpose: voice notes carry meaningless
               recorder-generated names. The size still hints at length. */
            string size = message.file_bytes > 0
                ? " (%s)".printf (format_size (message.file_bytes))
                : "";
            var label = new Gtk.Label ("Voice Message" + size);
            label.add_css_class ("message-audio-name");
            label.xalign = 0;
            label.valign = Gtk.Align.CENTER;
            row.append (label);

            if (Transcriber.available () && message.has_local_file) {
                transcribe_btn = new Gtk.Button.with_label ("A");
                transcribe_btn.add_css_class ("flat");
                transcribe_btn.add_css_class ("message-transcribe-button");
                transcribe_btn.valign = Gtk.Align.CENTER;
                transcribe_btn.tooltip_text = "Transcribe voice message";
                transcribe_btn.clicked.connect (() => {
                    transcriber.transcribe (message.file_path);
                });
                row.append (transcribe_btn);
            }
            append (row);

            transcription_label = new Gtk.Label ("");
            transcription_label.add_css_class ("message-transcription");
            transcription_label.visible = false;
            transcription_label.wrap = true;
            transcription_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
            transcription_label.max_width_chars = 42;
            transcription_label.xalign = 0;
            transcription_label.halign = Gtk.Align.START;
            transcription_label.selectable = true;
            append (transcription_label);

            current_handler = playback.notify["current-item"].connect (
                update_visuals);
            playing_handler = playback.notify["playing"].connect (update_visuals);
            transcriber_handler = transcriber.updated.connect ((path) => {
                if (path == message.file_path) update_transcription ();
            });
            update_visuals ();
            update_transcription ();
        }

        /** Reflect the in-memory transcription state: a progress note while
            whisper runs, then the quoted text. Never persisted anywhere. */
        private void update_transcription () {
            string? path = message.file_path;
            if (path == null) return;
            bool in_progress = transcriber.is_running (path);
            string? text = transcriber.result_for (path);
            if (transcribe_btn != null) {
                transcribe_btn.sensitive = !in_progress && text == null;
            }
            if (in_progress) {
                transcription_label.set_markup ("<i>Transcribing…</i>");
                transcription_label.visible = true;
            } else if (text != null) {
                string quoted = text.length > 0
                    ? "“" + Markup.escape_text (text) + "”"
                    : "(no speech detected)";
                transcription_label.set_markup (
                    "Transcription: <i>" + quoted + "</i>");
                transcription_label.visible = true;
            } else {
                transcription_label.visible = false;
            }
        }

        private void update_visuals () {
            bool is_playing = is_current_message () && playback.playing;
            btn.icon_name = is_playing
                ? "media-playback-pause-symbolic"
                : "media-playback-start-symbolic";
            btn.tooltip_text = is_playing ? "Pause" : "Play";
        }

        private bool is_current_message () {
            var item = playback.current_item;
            return item != null && item.account_id == account_id
                && item.chat_id == message.chat_id
                && item.message_id == message.id;
        }

        public override void dispose () {
            if (current_handler != 0) {
                playback.disconnect (current_handler);
                current_handler = 0;
            }
            if (playing_handler != 0) {
                playback.disconnect (playing_handler);
                playing_handler = 0;
            }
            if (transcriber_handler != 0) {
                transcriber.disconnect (transcriber_handler);
                transcriber_handler = 0;
            }
            base.dispose ();
        }
    }
}
