namespace Dc {

    /**
     * Downloads and installs a Parla-owned `deltachat-rpc-server` binary into
     * Parla's private data directory (~/.local/share/parla/bin). This is a
     * last-resort fallback for source/unpackaged installs: distro, Flatpak and
     * system binaries always take precedence (see AccountFinder). The managed
     * binary is fetched from the upstream chatmail/core GitHub releases.
     *
     * The HTTP/TLS plumbing is intentionally dependency-free (GIO sockets +
     * TlsClientConnection) to keep Parla self-contained.
     */
    public class RpcInstaller : Object {

        private const string RPC_BIN = "deltachat-rpc-server";
        private const int MAX_REDIRECTS = 5;

        /** Emitted while downloading. `total` is -1 when the size is unknown. */
        public signal void progress (int64 received, int64 total);

        /** Directory Parla owns for the downloaded server, created on demand. */
        public static string managed_dir () {
            return Path.build_filename (AccountFinder.get_parla_data_dir (), "bin");
        }

        /** Absolute path to the Parla-managed server binary. */
        public static string managed_bin_path () {
            return Path.build_filename (managed_dir (), RPC_BIN);
        }

        /**
         * Name of the GitHub release asset matching the host architecture, or
         * null when no prebuilt Linux binary is published for this machine.
         */
        public static string? detect_asset_name () {
            string? arch = detect_arch ();
            if (arch == null) return null;
            return "%s-%s-linux".printf (RPC_BIN, arch);
        }

        /**
         * Detect the host architecture, mapped to upstream asset naming. We read
         * the ELF e_machine field of our own executable first (no subprocess),
         * and fall back to `uname -m`.
         */
        private static string? detect_arch () {
            string? from_elf = arch_from_self_elf ();
            if (from_elf != null) return from_elf;
            return arch_from_uname ();
        }

        private static string? arch_from_self_elf () {
            try {
                uint8[] header = new uint8[20];
                var stream = File.new_for_path ("/proc/self/exe").read ();
                size_t got;
                stream.read_all (header, out got);
                stream.close ();
                if (got < 20) return null;
                if (header[0] != 0x7f || header[1] != 'E'
                    || header[2] != 'L' || header[3] != 'F') {
                    return null;
                }
                /* e_machine is a 16-bit little-endian field at offset 18. */
                int machine = header[18] | (header[19] << 8);
                switch (machine) {
                case 0x3e: return "x86_64";   // EM_X86_64
                case 0xb7: return "aarch64";  // EM_AARCH64
                case 0x28: return "armv7l";   // EM_ARM
                case 0x03: return "i686";     // EM_386
                default: return null;
                }
            } catch (Error e) {
                return null;
            }
        }

        private static string? arch_from_uname () {
            try {
                string output;
                Process.spawn_command_line_sync ("uname -m", out output);
                string m = output.strip ();
                switch (m) {
                case "x86_64": return "x86_64";
                case "aarch64":
                case "arm64": return "aarch64";
                case "armv7l": return "armv7l";
                case "armv6l": return "armv6l";
                case "i686":
                case "i386": return "i686";
                default: return null;
                }
            } catch (SpawnError e) {
                return null;
            }
        }

        /** Read the installed managed binary's --version string, or null. */
        public static async string? installed_version () {
            string path = managed_bin_path ();
            if (!FileUtils.test (path, FileTest.IS_EXECUTABLE)) return null;
            try {
                var process = new Subprocess (
                    SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE,
                    path, "--version");
                string? stdout_buf;
                string? stderr_buf;
                yield process.communicate_utf8_async (
                    null, null, out stdout_buf, out stderr_buf);
                string version = ((stdout_buf ?? "").strip ().length > 0)
                    ? (stdout_buf ?? "").strip ()
                    : (stderr_buf ?? "").strip ();
                return (process.get_successful () && version.length > 0)
                    ? version : null;
            } catch (Error e) {
                return null;
            }
        }

        /**
         * Resolve the latest upstream release tag (e.g. "v2.51.0") by following
         * the redirect from the GitHub "latest" release URL.
         */
        public static async string fetch_latest_tag () throws Error {
            var client = new SocketClient ();
            client.timeout = 15;
            var tcp = yield client.connect_to_host_async ("github.com", 443, null);
            var identity = new NetworkAddress ("github.com", 443);
            var tls = TlsClientConnection.new (tcp, identity);
            if (tls == null) {
                throw new IOError.FAILED ("Unable to create TLS connection");
            }
            yield tls.handshake_async (Priority.DEFAULT, null);

            string request =
                "HEAD /chatmail/core/releases/latest HTTP/1.1\r\n" +
                "Host: github.com\r\n" +
                "User-Agent: Parla\r\n" +
                "Accept: */*\r\n" +
                "Connection: close\r\n\r\n";

            size_t written;
            yield tls.output_stream.write_all_async (
                request.data, Priority.DEFAULT, null, out written);

            var reader = new DataInputStream (tls.input_stream);
            reader.set_newline_type (DataStreamNewlineType.LF);

            size_t len;
            string? status_line = yield reader.read_line_utf8_async (
                Priority.DEFAULT, null, out len);
            int status = parse_http_status (status_line ?? "");
            string? location = null;

            string? line;
            while ((line = yield reader.read_line_utf8_async (
                        Priority.DEFAULT, null, out len)) != null) {
                string stripped = line.strip ();
                if (stripped.length == 0) break;
                if (stripped.down ().has_prefix ("location:")) {
                    location = stripped.substring ("location:".length).strip ();
                }
            }

            try {
                yield tls.close_async (Priority.DEFAULT, null);
            } catch (Error e) {
                /* The response has already been read. */
            }

            if (status < 300 || status >= 400 || location == null) {
                throw new IOError.FAILED (
                    "GitHub returned HTTP status %d".printf (status));
            }

            string? tag = extract_release_tag (location);
            if (tag == null) {
                throw new IOError.FAILED ("GitHub response did not include a release tag");
            }
            return tag;
        }

        /**
         * Download the latest matching server release into the managed
         * directory and atomically install it. Returns the installed path.
         */
        public async string download_latest () throws Error {
            string? asset = detect_asset_name ();
            if (asset == null) {
                throw new IOError.NOT_SUPPORTED (
                    "No prebuilt deltachat-rpc-server is published for this architecture");
            }
            string dir = managed_dir ();
            DirUtils.create_with_parents (dir, 0700);

            string tag = yield fetch_latest_tag ();
            string url =
                "https://github.com/chatmail/core/releases/download/%s/%s".printf (
                    tag, asset);
            string tmp = Path.build_filename (dir, ".%s.download".printf (RPC_BIN));
            FileUtils.unlink (tmp);

            try {
                yield https_get_to_file (url, tmp, 0);
                if (!is_elf (tmp)) {
                    throw new IOError.INVALID_DATA (
                        "Downloaded file is not a valid executable");
                }
                if (FileUtils.chmod (tmp, 0755) != 0) {
                    throw new IOError.FAILED ("Could not make the server executable");
                }
                string final_path = managed_bin_path ();
                FileUtils.unlink (final_path);
                if (FileUtils.rename (tmp, final_path) != 0) {
                    throw new IOError.FAILED ("Could not install the server binary");
                }
                return final_path;
            } catch (Error e) {
                FileUtils.unlink (tmp);
                throw e;
            }
        }

        /**
         * Stream an HTTPS GET to a file, following redirects across hosts.
         */
        private async void https_get_to_file (string url, string dest, int depth)
                throws Error {
            if (depth > MAX_REDIRECTS) {
                throw new IOError.FAILED ("Too many HTTP redirects");
            }

            /* ENCODED keeps the query percent-encoded; GitHub's signed asset
               URLs reject any re-encoding, so the components must pass through
               verbatim. */
            var uri = Uri.parse (url, UriFlags.ENCODED);
            string host = uri.get_host ();
            int port = uri.get_port ();
            if (port <= 0) port = 443;
            string path = uri.get_path ();
            if (path.length == 0) path = "/";
            string? query = uri.get_query ();
            string target = (query != null && query.length > 0)
                ? "%s?%s".printf (path, query) : path;

            var client = new SocketClient ();
            client.timeout = 60;
            var tcp = yield client.connect_to_host_async (host, (uint16) port, null);
            var identity = new NetworkAddress (host, (uint16) port);
            var tls = TlsClientConnection.new (tcp, identity);
            if (tls == null) {
                throw new IOError.FAILED ("Unable to create TLS connection");
            }
            yield tls.handshake_async (Priority.DEFAULT, null);

            string request =
                "GET %s HTTP/1.1\r\n".printf (target) +
                "Host: %s\r\n".printf (host) +
                "User-Agent: Parla\r\n" +
                "Accept: */*\r\n" +
                "Connection: close\r\n\r\n";

            size_t written;
            yield tls.output_stream.write_all_async (
                request.data, Priority.DEFAULT, null, out written);

            var reader = new DataInputStream (tls.input_stream);
            reader.set_newline_type (DataStreamNewlineType.LF);
            reader.set_buffer_size (65536);

            size_t len;
            string? status_line = yield reader.read_line_utf8_async (
                Priority.DEFAULT, null, out len);
            int status = parse_http_status (status_line ?? "");

            string? location = null;
            int64 content_length = -1;
            string? line;
            while ((line = yield reader.read_line_utf8_async (
                        Priority.DEFAULT, null, out len)) != null) {
                string stripped = line.strip ();
                if (stripped.length == 0) break;
                string lower = stripped.down ();
                if (lower.has_prefix ("location:")) {
                    location = stripped.substring ("location:".length).strip ();
                } else if (lower.has_prefix ("content-length:")) {
                    content_length = int64.parse (
                        stripped.substring ("content-length:".length).strip ());
                }
            }

            if (status >= 300 && status < 400) {
                try { yield tls.close_async (Priority.DEFAULT, null); }
                catch (Error e) { /* ignore */ }
                if (location == null) {
                    throw new IOError.FAILED (
                        "Redirect (%d) without a Location header".printf (status));
                }
                yield https_get_to_file (location, dest, depth + 1);
                return;
            }

            if (status < 200 || status >= 300) {
                try { yield tls.close_async (Priority.DEFAULT, null); }
                catch (Error e) { /* ignore */ }
                throw new IOError.FAILED (
                    "Download failed with HTTP status %d".printf (status));
            }

            var fos = File.new_for_path (dest).replace (
                null, false, FileCreateFlags.REPLACE_DESTINATION);
            uint8[] buf = new uint8[65536];
            int64 received = 0;
            progress (0, content_length);
            while (true) {
                ssize_t n = yield reader.read_async (buf, Priority.DEFAULT, null);
                if (n <= 0) break;
                size_t bw;
                fos.write_all (buf[0:(int) n], out bw);
                received += n;
                progress (received, content_length);
            }
            yield fos.close_async (Priority.DEFAULT, null);

            try { yield tls.close_async (Priority.DEFAULT, null); }
            catch (Error e) { /* ignore */ }

            if (content_length > 0 && received < content_length) {
                throw new IOError.PARTIAL_INPUT (
                    "Download truncated (%lld of %lld bytes)".printf (
                        received, content_length));
            }
        }

        private static bool is_elf (string path) {
            try {
                uint8[] magic = new uint8[4];
                var stream = File.new_for_path (path).read ();
                size_t got;
                stream.read_all (magic, out got);
                stream.close ();
                return got == 4 && magic[0] == 0x7f && magic[1] == 'E'
                    && magic[2] == 'L' && magic[3] == 'F';
            } catch (Error e) {
                return false;
            }
        }

        private static int parse_http_status (string status_line) {
            string[] parts = status_line.split (" ");
            if (parts.length < 2) return 0;
            return int.parse (parts[1]);
        }

        /** Extract a dotted numeric version (e.g. "2.51.0") from arbitrary text. */
        public static string? extract_version (string text) {
            int start = -1;
            int end = -1;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (start < 0) {
                    if (c >= '0' && c <= '9') {
                        start = i;
                        end = i + 1;
                    }
                } else if ((c >= '0' && c <= '9') || c == '.') {
                    end = i + 1;
                } else {
                    break;
                }
            }
            if (start < 0 || end <= start) return null;

            string version = text.substring (start, end - start);
            while (version.has_suffix (".")) {
                version = version.substring (0, version.length - 1);
            }
            return version.length > 0 ? version : null;
        }

        private static string? extract_release_tag (string location) {
            int idx = location.last_index_of ("/tag/");
            if (idx < 0) return null;

            string tag = location.substring (idx + "/tag/".length);
            int q = tag.index_of ("?");
            if (q >= 0) tag = tag.substring (0, q);
            int hash = tag.index_of ("#");
            if (hash >= 0) tag = tag.substring (0, hash);
            tag = tag.strip ();
            return tag.length > 0 ? tag : null;
        }
    }
}
