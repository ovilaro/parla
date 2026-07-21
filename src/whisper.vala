namespace Dc {

    /**
     * Transcribes voice messages with the external `whisper` CLI.
     * Results live only in this process: nothing is written back to the
     * message or to disk, so closing Parla forgets every transcription.
     */
    public class Transcriber : Object {

        private static Transcriber? instance = null;

        private HashTable<string, string> results =
            new HashTable<string, string> (str_hash, str_equal);
        private GenericSet<string> running =
            new GenericSet<string> (str_hash, str_equal);

        /** Emitted when the transcription state for a file path changes. */
        public signal void updated (string path);

        public static Transcriber shared () {
            if (instance == null) instance = new Transcriber ();
            return instance;
        }

        public static bool available () {
            return Environment.find_program_in_path ("whisper") != null;
        }

        /** Finished transcription for path, or null when none ran yet. An
            empty string means the tool produced no usable output. */
        public string? result_for (string path) {
            return results.lookup (path);
        }

        public bool is_running (string path) {
            return running.contains (path);
        }

        public void transcribe (string path) {
            if (!available ()) return;
            if (running.contains (path) || results.contains (path)) return;
            running.add (path);
            updated (path);
            run_whisper.begin (path);
        }

        private async void run_whisper (string path) {
            string text = "";
            try {
                string[] argv = {
                    "whisper", path,
                    "--model", "base",
                    "--output_format", "txt",
                    "--fp16", "False"
                };
                var launcher = new GLib.SubprocessLauncher (
                    SubprocessFlags.STDOUT_PIPE
                    | SubprocessFlags.STDERR_SILENCE);
                /* whisper drops .txt/.srt/.json transcript files into its
                   working directory; keep that litter in the cache dir. */
                launcher.set_cwd (work_dir ());
                var proc = launcher.spawnv (argv);
                string stdout_buf;
                string stderr_buf;
                yield proc.communicate_utf8_async (null, null,
                    out stdout_buf, out stderr_buf);
                text = parse_output (stdout_buf ?? "");
            } catch (Error e) {
                warning ("transcribe: %s failed: %s", path, e.message);
            }
            running.remove (path);
            results.insert (path, text);
            updated (path);
        }

        private static string work_dir () {
            string dir = Path.build_filename (
                Environment.get_user_cache_dir (), "parla", "transcribe");
            DirUtils.create_with_parents (dir, 0700);
            return dir;
        }

        /**
         * The python tool ignores --output_format on stdout, so scrape its
         * human-readable progress lines instead:
         *   [00:00.800 --> 00:07.160]  Si no me escribes por Telegram...
         * Every line starting with '[' contributes the text after its first
         * ']'; everything else (warnings, language detection) is noise.
         */
        public static string parse_output (string output) {
            var sb = new StringBuilder ();
            foreach (string line in output.split ("\n")) {
                if (!line.has_prefix ("[")) continue;
                int idx = line.index_of ("]");
                if (idx < 0) continue;
                string text = line.substring (idx + 1).strip ();
                if (text.length == 0) continue;
                if (sb.len > 0) sb.append_c ('\n');
                sb.append (text);
            }
            return sb.str;
        }
    }
}
