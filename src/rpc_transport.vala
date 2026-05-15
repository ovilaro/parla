namespace Dc {

    /**
     * JSON-RPC transport for deltachat-rpc-server over stdio.
     * Owns the subprocess, request ids, pending calls, and read loop.
     */
    public class RpcTransport : Object {

        private Subprocess? process = null;
        private DataInputStream? reader = null;
        private OutputStream? writer = null;
        private int next_id = 1;
        private GenericArray<PendingCall> pending = new GenericArray<PendingCall> ();
        private string last_stderr = "";

        public signal void disconnected (string reason);

        public bool is_connected { get; private set; default = false; }

        public async void start (string[] argv, string? cwd = null,
                                   string? accounts_path = null) throws Error {
            last_stderr = "";
            var flags = SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE
                        | SubprocessFlags.STDERR_PIPE;
            var launcher = new SubprocessLauncher (flags);
            if (cwd != null) {
                launcher.set_cwd (cwd);
            }
            if (accounts_path != null) {
                launcher.setenv ("DC_ACCOUNTS_PATH", accounts_path, true);
            }
            process = launcher.spawnv (argv);
            writer = process.get_stdin_pipe ();
            reader = new DataInputStream (process.get_stdout_pipe ());
            reader.set_newline_type (DataStreamNewlineType.LF);

            drain_stderr.begin ();
            read_loop.begin ();

            try {
                yield call ("get_system_info", Params.begin ().build ());
            } catch (Error e) {
                yield nap (200);
                if (last_stderr.length > 0) {
                    throw new IOError.FAILED ("%s", last_stderr);
                }
                throw e;
            }
            is_connected = true;
        }

        public void stop () {
            is_connected = false;
            fail_pending ("RPC client stopped");
            if (process != null) {
                process.force_exit ();
                process = null;
            }
            writer = null;
            reader = null;
        }

        public async Json.Node? call (string method, Json.Node params) throws Error {
            if (writer == null || reader == null) {
                throw new IOError.NOT_CONNECTED ("RPC client not connected");
            }

            int id = next_id++;
            var pc = new PendingCall (id);
            pc.callback = call.callback;
            pending.add (pc);

            try {
                send_request (id, method, params);
            } catch (Error e) {
                remove_pending (id);
                throw e;
            }

            yield;

            remove_pending (id);

            if (pc.error_msg != null) {
                throw new IOError.FAILED ("RPC %s: %s", method, pc.error_msg);
            }
            return pc.result;
        }

        private async void drain_stderr () {
            if (process == null) return;
            try {
                var err_stream = new DataInputStream (process.get_stderr_pipe ());
                string? line;
                size_t len;
                while ((line = yield err_stream.read_line_utf8_async (
                            Priority.DEFAULT, null, out len)) != null) {
                    last_stderr = line.strip ();
                }
            } catch (Error e) {
                /* ignore */
            }
        }

        private async void read_loop () {
            try {
                while (true) {
                    size_t len;
                    string? line = yield reader.read_line_utf8_async (
                        Priority.DEFAULT, null, out len);
                    if (line == null) break;
                    if (line.strip ().length == 0) continue;

                    var parser = new Json.Parser ();
                    parser.load_from_data (line);
                    var root = parser.get_root ();
                    if (root == null || root.get_node_type () != Json.NodeType.OBJECT)
                        continue;

                    var obj = root.get_object ();
                    if (!obj.has_member ("id")) continue;

                    int resp_id = (int) obj.get_int_member ("id");
                    PendingCall? pc = find_pending (resp_id);
                    if (pc == null) continue;

                    if (obj.has_member ("error") &&
                        !obj.get_member ("error").is_null ()) {
                        var err = obj.get_object_member ("error");
                        pc.error_msg = err.has_member ("message")
                            ? err.get_string_member ("message")
                            : "Unknown RPC error";
                    } else if (obj.has_member ("result")) {
                        var result_member = obj.get_member ("result");
                        pc.result = (result_member != null) ? result_member.copy () : null;
                    }

                    resume_pending (pc);
                }
            } catch (Error e) {
                warning ("RPC read loop error: %s", e.message);
            }

            string reason = "RPC server closed";
            is_connected = false;
            fail_pending (reason);
            disconnected (reason);
        }

        private void send_request (int id, string method, Json.Node params) throws Error {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("jsonrpc"); b.add_string_value ("2.0");
            b.set_member_name ("id");      b.add_int_value (id);
            b.set_member_name ("method");  b.add_string_value (method);
            b.set_member_name ("params");  b.add_value (params);
            b.end_object ();

            var gen = new Json.Generator ();
            gen.set_root (b.get_root ());
            size_t json_len;
            string json = gen.to_data (out json_len);
            string line = json + "\n";

            size_t written;
            writer.write_all (line.data, out written);
            writer.flush ();
        }

        private PendingCall? find_pending (int id) {
            for (int i = 0; i < pending.length; i++) {
                if (pending[i].id == id) return pending[i];
            }
            return null;
        }

        private void remove_pending (int id) {
            for (int i = 0; i < pending.length; i++) {
                if (pending[i].id == id) {
                    pending.remove_index (i);
                    return;
                }
            }
        }

        private void fail_pending (string reason) {
            for (int i = 0; i < pending.length; i++) {
                pending[i].error_msg = reason;
                resume_pending (pending[i]);
            }
        }

        private void resume_pending (PendingCall pc) {
            if (pc.callback == null) return;
            var cb = (owned) pc.callback;
            pc.callback = null;
            Idle.add ((owned) cb);
        }

        private async void nap (uint ms) {
            Timeout.add (ms, nap.callback);
            yield;
        }
    }

    private class PendingCall {
        public int id;
        public SourceFunc? callback = null;
        public Json.Node? result = null;
        public string? error_msg = null;

        public PendingCall (int id) {
            this.id = id;
        }
    }
}
