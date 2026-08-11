namespace Dc {

    /* Mono AAC recorder with GStreamer/FFmpeg fallback. */
    public class AudioRecorder : Object {

        public string output_path { get; private set; default = ""; }

        private bool prefer_external;
        private bool tried_gstreamer;
        private bool tried_ffmpeg;
        private bool using_ffmpeg;
        private Subprocess? process;
        private bool stop_requested;
        private bool timed_out;
        private uint stop_timeout;

        public signal void completed ();
        public signal void failed (string message);

        public AudioRecorder (bool prefer_external) {
            this.prefer_external = prefer_external;
        }

        public void start () throws Error {
            if (process != null || output_path.length > 0)
                throw new IOError.BUSY ("An audio recording is already active");

            FileIOStream stream;
            output_path = File.new_tmp (
                "parla-voice-XXXXXX.m4a", out stream).get_path ();
            stream.close ();
            if (!spawn_next ()) {
                discard_output ();
                throw new IOError.NOT_SUPPORTED (
                    "Install GStreamer or FFmpeg to record voice messages");
            }
        }

        public void stop () {
            var active = process;
            if (active == null || stop_requested) return;

            stop_requested = true;
            if (using_ffmpeg) {
                try {
                    var input = active.get_stdin_pipe ();
                    if (input != null) {
                        size_t written;
                        input.write_all ("q\n".data, out written);
                        input.close ();
                    }
                } catch (Error e) {
                    active.force_exit ();
                }
            } else {
#if WINDOWS
                active.force_exit ();
#else
                /* gst-launch -e converts SIGINT to EOS and finalizes mp4mux. */
                active.send_signal ((int) Posix.Signal.INT);
#endif
            }

            stop_timeout = Timeout.add_seconds (8, () => {
                stop_timeout = 0;
                if (process == active) {
                    timed_out = true;
                    active.force_exit ();
                }
                return Source.REMOVE;
            });
        }

        public string take_output () {
            string path = output_path;
            output_path = "";
            return path;
        }

        public void cancel () {
            clear_stop_timeout ();
            var active = process;
            process = null;
            if (active != null) active.force_exit ();
            discard_output ();
        }

        private bool spawn_next () {
            bool[] order = { prefer_external, !prefer_external };
            foreach (bool ffmpeg in order) {
                if (ffmpeg ? tried_ffmpeg : tried_gstreamer) continue;
                if (ffmpeg) tried_ffmpeg = true;
                else tried_gstreamer = true;

                string[]? argv = ffmpeg
                    ? ffmpeg_command (output_path)
                    : gstreamer_command (output_path);
                if (argv == null) continue;

                FileUtils.unlink (output_path);
                try {
                    var launcher = new SubprocessLauncher (
                        SubprocessFlags.STDIN_PIPE
                        | SubprocessFlags.STDOUT_SILENCE
                        | SubprocessFlags.STDERR_SILENCE);
                    var child = SubprocessUtil.spawnv (launcher, argv);
                    process = child;
                    using_ffmpeg = ffmpeg;
                    child.wait_async.begin (null, (obj, res) => {
                        try { child.wait_async.end (res); }
                        catch (Error e) {}
                        on_process_exit (child);
                    });
                    return true;
                } catch (Error e) {
                    warning ("audio recording: failed to spawn %s: %s",
                        argv[0], e.message);
                }
            }
            return false;
        }

        private void on_process_exit (Subprocess child) {
            if (process != child) return;
            process = null;
            clear_stop_timeout ();

            if (stop_requested) {
                if (!timed_out && output_size () > 512) {
                    completed ();
                } else {
                    discard_output ();
                    failed (timed_out
                        ? "Audio recording did not stop cleanly"
                        : "The recording was too short or could not be encoded");
                }
                return;
            }
            if (spawn_next ()) return;

            discard_output ();
            failed ("Could not access the microphone; check microphone "
                + "permission and the configured media tools");
        }

        private void clear_stop_timeout () {
            if (stop_timeout == 0) return;
            Source.remove (stop_timeout);
            stop_timeout = 0;
        }

        private int64 output_size () {
            try {
                return File.new_for_path (output_path).query_info (
                    "standard::size", FileQueryInfoFlags.NONE).get_size ();
            } catch (Error e) {
                return 0;
            }
        }

        private void discard_output () {
            if (output_path.length == 0) return;
            FileUtils.unlink (take_output ());
        }

        private static string[]? gstreamer_command (string output) {
#if WINDOWS
            return null;
#else
            if (Environment.find_program_in_path ("gst-launch-1.0") == null)
                return null;
            return {
                "gst-launch-1.0", "-q", "-e",
                "autoaudiosrc", "!", "audioconvert", "!", "audioresample",
                "!", "audio/x-raw,rate=48000,channels=1", "!",
                "avenc_aac", "bitrate=64000", "!",
                "mp4mux", "faststart=true", "!",
                "filesink", "location=" + output
            };
#endif
        }

        private static string[]? ffmpeg_command (string output) {
            if (Environment.find_program_in_path ("ffmpeg") == null) return null;

            string format;
            string source;
#if WINDOWS
            format = "dshow";
            source = "audio=default";
#else
            bool macos = Platform.is_macos ();
            format = macos ? "avfoundation" : "pulse";
            source = macos ? ":0" : "default";
#endif
            return {
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-nostats",
                "-y", "-f", format, "-i", source, "-vn", "-ac", "1",
                "-ar", "48000", "-c:a", "aac", "-b:a", "64k",
                "-movflags", "+faststart", output
            };
        }
    }
}
