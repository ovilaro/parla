/* Experimental Webxdc runner: hosts a Delta Chat mini-app (.xdc archive)
 * inside a WebKitGTK view. Compiled only with -Dwebxdc=true; otherwise
 * webxdc_stub.vala provides the same entry points as no-ops so no other
 * file needs conditional compilation. See docs/webxdc.md for the security
 * boundaries and the exact JS API exposed to apps. */
namespace Dc.Webxdc {

    public const bool AVAILABLE = true;

    private HashTable<int, unowned AppWindow>? windows = null;

    public void open (Gtk.Window? parent, RpcClient rpc, Message msg) {
        if (windows == null) {
            windows = new HashTable<int, unowned AppWindow> (
                direct_hash, direct_equal);
        }
        var existing = windows.lookup (msg.id);
        if (existing != null) {
            existing.present ();
            return;
        }
        var win = new AppWindow (rpc, msg);
        windows.insert (msg.id, win);
        int id = msg.id;
        win.close_request.connect (() => {
            windows.remove (id);
            return false;
        });
        win.present ();
    }

    /** Routed from the WebxdcStatusUpdate core event. */
    public void status_update (int msg_id) {
        var win = windows == null ? null : windows.lookup (msg_id);
        if (win != null) win.pull_updates.begin ();
    }

    /** Routed from the WebxdcInstanceDeleted core event. */
    public void instance_deleted (int msg_id) {
        var win = windows == null ? null : windows.lookup (msg_id);
        if (win != null) win.close ();
    }

    private class AppWindow : Adw.Window {
        /* Strong ref on purpose: switching accounts replaces the shared
           RpcClient, and a still-open app must keep talking to the account
           it was started from (account_id is captured for the same reason). */
        private RpcClient rpc;
        private int account_id;
        private int msg_id;
        private WebKit.WebView view;
        private int64 last_serial = 0;
        private string self_addr = "unknown";
        private string self_name = "me";

        public AppWindow (RpcClient rpc, Message msg) {
            this.rpc = rpc;
            this.account_id = rpc.account_id;
            this.msg_id = msg.id;
            title = msg.display_file_name ("Webxdc");
            default_width = 420;
            default_height = 640;

            var ucm = new WebKit.UserContentManager ();
            ucm.register_script_message_handler ("webxdc", (string) null);
            ucm.script_message_received["webxdc"].connect (on_script_message);

            var ctx = new WebKit.WebContext ();
            ctx.register_uri_scheme ("webxdc", serve_request);
            var sec = ctx.get_security_manager ();
            sec.register_uri_scheme_as_secure ("webxdc");
            sec.register_uri_scheme_as_local ("webxdc");

            /* No cookies/cache on disk, and a blackhole proxy so any
               http(s) request an app may attempt dies before reaching the
               network. webxdc: URIs are served in-process and unaffected. */
            var session = new WebKit.NetworkSession.ephemeral ();
            session.set_proxy_settings (WebKit.NetworkProxyMode.CUSTOM,
                new WebKit.NetworkProxySettings ("socks5://127.0.0.1:1", null));

            view = (WebKit.WebView) GLib.Object.new (typeof (WebKit.WebView),
                "web-context", ctx,
                "network-session", session,
                "user-content-manager", ucm);
            var s = view.get_settings ();
            s.enable_developer_extras = false;
            s.allow_modal_dialogs = false;
            s.javascript_can_open_windows_automatically = false;
            view.decide_policy.connect (on_decide_policy);
            view.vexpand = true;

            var toolbar = new Adw.ToolbarView ();
            toolbar.add_top_bar (new Adw.HeaderBar ());
            toolbar.content = view;
            content = toolbar;

            start.begin ();
        }

        private async void start () {
            try {
                var info = yield rpc.call ("get_webxdc_info", Params.begin ()
                    .add_int (account_id).add_int (msg_id).build ());
                var obj = info.get_object ();
                var name = obj.get_string_member_with_default ("name", "");
                if (name.length > 0) title = name;
            } catch (Error e) {
                warning ("webxdc info: %s", e.message);
            }
            try {
                var dn = yield rpc.get_config ("displayname", account_id);
                if (dn != null && dn.length > 0) self_name = dn;
                else if (rpc.self_email != null) self_name = rpc.self_email;
                if (rpc.self_email != null) self_addr = rpc.self_email;
            } catch (Error e) {
                warning ("webxdc config: %s", e.message);
            }
            view.load_uri ("webxdc://app/index.html");
        }

        /* Everything the page loads is pulled out of the .xdc archive by
           deltachat core (get_webxdc_blob); nothing is read from disk or
           the network. webxdc.js itself is the one synthetic file. */
        private void serve_request (WebKit.URISchemeRequest req) {
            string path = req.get_path () ?? "";
            if (path.has_prefix ("/")) path = path.substring (1);
            if (path.length == 0) path = "index.html";
            if (Path.get_basename (path) == "webxdc.js") {
                var js = bridge_js ();
                var stream = new MemoryInputStream.from_bytes (
                    new Bytes (js.data));
                req.finish (stream, js.length, "text/javascript");
                return;
            }
            serve_blob.begin (req, path);
        }

        private async void serve_blob (WebKit.URISchemeRequest req,
                                       string path) {
            try {
                var res = yield rpc.call ("get_webxdc_blob", Params.begin ()
                    .add_int (account_id).add_int (msg_id)
                    .add_string (path).build ());
                var data = Base64.decode (res.get_string ());
                bool uncertain;
                string ctype = ContentType.guess (path, data, out uncertain);
                string mime = ContentType.get_mime_type (ctype)
                    ?? "application/octet-stream";
                var stream = new MemoryInputStream.from_bytes (
                    new Bytes ((owned) data));
                req.finish (stream, -1, mime);
            } catch (Error e) {
                req.finish_error (new IOError.NOT_FOUND (
                    "webxdc blob '%s': %s", path, e.message));
            }
        }

        /* The app may only navigate inside its own scheme; anything else
           (http links, window.open) is refused. */
        private bool on_decide_policy (WebKit.PolicyDecision decision,
                                       WebKit.PolicyDecisionType type) {
            if (type == WebKit.PolicyDecisionType.NAVIGATION_ACTION
                || type == WebKit.PolicyDecisionType.NEW_WINDOW_ACTION) {
                var nav = (WebKit.NavigationPolicyDecision) decision;
                var uri = nav.navigation_action.get_request ().get_uri ();
                if (!uri.has_prefix ("webxdc:")) {
                    decision.ignore ();
                    return true;
                }
            }
            return false;
        }

        private static string js_str (string s) {
            var node = new Json.Node (Json.NodeType.VALUE);
            node.set_string (s);
            return Json.to_string (node, false);
        }

        /* The window.webxdc object, limited to the documented API used by
           the official Delta Chat clients: selfAddr, selfName, sendUpdate
           and setUpdateListener. Serial de-duplication happens here so a
           pull racing an event push never delivers an update twice. */
        private string bridge_js () {
            return """window.webxdc = (function () {
    'use strict';
    var handler = window.webkit.messageHandlers.webxdc;
    var listener = null;
    var last = 0;
    window.__webxdc_deliver = function (updates) {
        updates.forEach(function (u) {
            if (u.serial > last) {
                last = u.serial;
                if (listener) listener(u);
            }
        });
    };
    return {
        selfAddr: %s,
        selfName: %s,
        sendUpdate: function (update, description) {
            handler.postMessage(JSON.stringify({ type: 'send', update: update }));
        },
        setUpdateListener: function (cb, serial) {
            listener = cb;
            last = serial || 0;
            handler.postMessage(JSON.stringify({ type: 'pull', serial: last }));
            return Promise.resolve();
        }
    };
})();
""".printf (js_str (self_addr), js_str (self_name));
        }

        private void on_script_message (JSC.Value value) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (value.to_string ());
                var obj = parser.get_root ().get_object ();
                switch (obj.get_string_member_with_default ("type", "")) {
                case "send":
                    var member = obj.get_member ("update");
                    if (member == null) break;
                    var update = Json.to_string (member, false);
                    rpc.call.begin ("send_webxdc_status_update",
                        Params.begin ().add_int (account_id).add_int (msg_id)
                            .add_string (update).add_string ("").build ());
                    break;
                case "pull":
                    last_serial = obj.get_int_member_with_default ("serial", 0);
                    pull_updates.begin ();
                    break;
                }
            } catch (Error e) {
                warning ("webxdc message: %s", e.message);
            }
        }

        /** Fetch status updates newer than last_serial and hand them to the
            page. Called on setUpdateListener and on core events. */
        public async void pull_updates () {
            string updates;
            try {
                var res = yield rpc.call ("get_webxdc_status_updates",
                    Params.begin ().add_int (account_id).add_int (msg_id)
                        .add_int ((int) last_serial).build ());
                updates = res.get_string ();
                var parser = new Json.Parser ();
                parser.load_from_data (updates);
                var arr = parser.get_root ().get_array ();
                if (arr.get_length () == 0) return;
                for (uint i = 0; i < arr.get_length (); i++) {
                    int64 serial = arr.get_object_element (i)
                        .get_int_member_with_default ("serial", 0);
                    if (serial > last_serial) last_serial = serial;
                }
            } catch (Error e) {
                warning ("webxdc updates: %s", e.message);
                return;
            }
            view.evaluate_javascript.begin (
                "window.__webxdc_deliver(%s)".printf (updates), -1,
                null, null, null);
        }
    }
}
