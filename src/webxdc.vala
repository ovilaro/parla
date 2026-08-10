/* Experimental Webxdc runner: hosts a Delta Chat mini-app (.xdc archive)
 * in a web view. Compiled only with -Dwebxdc=true; otherwise
 * webxdc_stub.vala provides the same entry points as no-ops so no other
 * file needs conditional compilation. The jsonrpc plumbing and the JS
 * bridge below are platform-independent; only the view layer splits:
 * WebKitGTK on GNOME, the system WebKit.framework through the shim in
 * webxdc_macos.m on macOS (where WebKitGTK is not available). See
 * docs/webxdc.md for the security boundaries and the JS API. */
namespace Dc.Webxdc {

    public const bool AVAILABLE = true;

    private HashTable<int, Instance>? windows = null;

    /* Client used for chat-card lookups (window title/icon before an app
       is started); set from window.vala whenever the RpcClient changes.
       Strong ref so a lookup racing an account switch stays valid. */
    private RpcClient? client = null;
    private unowned SettingsManager? config = null;

    public void setup (RpcClient rpc, SettingsManager settings) {
        client = rpc;
        config = settings;
        cards = null;   /* msg ids are per-account */
    }

    /** Compile-time support plus the runtime settings toggle. */
    public bool enabled () {
        return config == null || config.webxdc_apps;
    }

    public class CardInfo {
        public string? name;
        public Gdk.Texture? icon;
    }

    private HashTable<int, CardInfo>? cards = null;

    /** App name and icon for the chat/gallery card, cached per message. */
    public async CardInfo card_info (int msg_id) {
        if (cards == null) {
            cards = new HashTable<int, CardInfo> (direct_hash, direct_equal);
        }
        var hit = cards.lookup (msg_id);
        if (hit != null) return hit;
        return yield fetch_card_info (msg_id);
    }

    private async CardInfo fetch_card_info (int msg_id) {
        var info = new CardInfo ();
        var rpc = client;
        if (rpc == null) return info;
        int acct = rpc.account_id;
        try {
            var res = yield rpc.call ("get_webxdc_info", Params.begin ()
                .add_int (acct).add_int (msg_id).build ());
            var obj = res.get_object ();
            var name = obj.get_string_member_with_default ("name", "");
            if (name.length > 0) info.name = name;
            var icon = obj.get_string_member_with_default ("icon", "");
            if (icon.length > 0) {
                var blob = yield rpc.call ("get_webxdc_blob", Params.begin ()
                    .add_int (acct).add_int (msg_id)
                    .add_string (icon).build ());
                info.icon = Gdk.Texture.from_bytes (
                    new Bytes (Base64.decode (blob.get_string ())));
            }
        } catch (Error e) {
            debug ("webxdc card info: %s", e.message);
        }
        cards.replace (msg_id, info);
        return info;
    }

    public void open (Gtk.Window? parent, RpcClient rpc, Message msg) {
        if (windows == null) {
            windows = new HashTable<int, Instance> (direct_hash, direct_equal);
        }
        var existing = windows.lookup (msg.id);
        if (existing != null) {
            existing.present ();
            return;
        }
        windows.insert (msg.id, new Instance (rpc, msg));
    }

    /** Routed from the WebxdcStatusUpdate core event. */
    public void status_update (int msg_id) {
        var app = windows == null ? null : windows.lookup (msg_id);
        if (app != null) app.pull_updates.begin ();
    }

    /** Routed from the WebxdcInstanceDeleted core event. */
    public void instance_deleted (int msg_id) {
        var app = windows == null ? null : windows.lookup (msg_id);
        if (app != null) app.close_view ();
    }

    private class Instance : Object {
        /* Strong ref on purpose: switching accounts replaces the shared
           RpcClient, and a still-open app must keep talking to the account
           it was started from (account_id is captured for the same reason). */
        private RpcClient rpc;
        private int account_id;
        private int msg_id;
        private int64 last_serial = 0;
        private string self_addr = "unknown";
        private string self_name = "me";

        public Instance (RpcClient rpc, Message msg) {
            this.rpc = rpc;
            this.account_id = rpc.account_id;
            this.msg_id = msg.id;
            create_view (msg.display_file_name ("Webxdc"));
            present ();
            start.begin ();
        }

        private async void start () {
            try {
                var info = yield rpc.call ("get_webxdc_info", Params.begin ()
                    .add_int (account_id).add_int (msg_id).build ());
                var name = info.get_object ()
                    .get_string_member_with_default ("name", "");
                if (name.length > 0) set_view_title (name);
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
            load_view ("webxdc://app/index.html");
        }

        /* Everything the page loads is pulled out of the .xdc archive by
           deltachat core (get_webxdc_blob); nothing is read from disk or
           the network. webxdc.js itself is the one synthetic file. */
#if MACOS
        private async void serve (string path, void* token) {
#else
        private async void serve (string path, WebKit.URISchemeRequest token) {
#endif
            string p = path.has_prefix ("/") ? path.substring (1) : path;
            if (p.length == 0) p = "index.html";
            if (Path.get_basename (p) == "webxdc.js") {
                deliver (token, bridge_js ().data, "text/javascript");
                return;
            }
            try {
                var res = yield rpc.call ("get_webxdc_blob", Params.begin ()
                    .add_int (account_id).add_int (msg_id)
                    .add_string (p).build ());
                var data = Base64.decode (res.get_string ());
                bool uncertain;
                string ctype = ContentType.guess (p, data, out uncertain);
                string mime = ContentType.get_mime_type (ctype)
                    ?? "application/octet-stream";
                deliver (token, data, mime);
            } catch (Error e) {
                warning ("webxdc blob '%s': %s", path, e.message);
                fail (token);
            }
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

        private void on_message (string json) {
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (json);
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
            eval_js ("window.__webxdc_deliver(%s)".printf (updates));
        }

        private void on_view_closed () {
            if (windows != null) windows.remove (msg_id);
        }

#if MACOS
        /* ============================================================
         *  View layer, macOS: NSWindow + WKWebView via webxdc_macos.m.
         *  The shim owns all AppKit state behind an opaque handle and
         *  re-queues every callback through g_idle_add, so this code
         *  always runs in normal GTK main-loop iterations.
         * ============================================================ */

        [CCode (has_target = false)]
        private delegate void RawBlobFn (string path, void* task,
                                         void* user_data);
        [CCode (has_target = false)]
        private delegate void RawMsgFn (string json, void* user_data);
        [CCode (has_target = false)]
        private delegate void RawClosedFn (void* user_data);

        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_open")]
        private static extern void* shim_open (string title, RawBlobFn blob,
                                               RawMsgFn message,
                                               RawClosedFn closed,
                                               void* user_data);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_load")]
        private static extern void shim_load (void* handle, string uri);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_finish_task")]
        private static extern void shim_finish_task (void* handle, void* task,
                                                     uint8[] data,
                                                     string mime);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_fail_task")]
        private static extern void shim_fail_task (void* handle, void* task);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_eval_js")]
        private static extern void shim_eval_js (void* handle, string js);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_set_title")]
        private static extern void shim_set_title (void* handle, string title);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_present")]
        private static extern void shim_present (void* handle);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_close")]
        private static extern void shim_close (void* handle);
        [CCode (cheader_filename = "webxdc_macos.h",
                cname = "parla_webxdc_free")]
        private static extern void shim_free (void* handle);

        private void* handle = null;

        /* The shim callbacks carry no closure; user_data is this instance,
           kept alive by the windows table until on_view_closed. */
        private static void on_raw_blob (string path, void* task,
                                         void* user_data) {
            unowned Instance self = (Instance) user_data;
            self.serve.begin (path, task);
        }

        private static void on_raw_message (string json, void* user_data) {
            unowned Instance self = (Instance) user_data;
            self.on_message (json);
        }

        private static void on_raw_closed (void* user_data) {
            unowned Instance self = (Instance) user_data;
            var h = self.handle;
            self.handle = null;
            if (h != null) shim_free (h);
            self.on_view_closed ();
        }

        private void create_view (string title) {
            handle = shim_open (title, on_raw_blob, on_raw_message,
                                on_raw_closed, this);
        }

        public void present () {
            if (handle != null) shim_present (handle);
        }

        private void load_view (string uri) {
            if (handle != null) shim_load (handle, uri);
        }

        private void set_view_title (string title) {
            if (handle != null) shim_set_title (handle, title);
        }

        private void eval_js (string js) {
            if (handle != null) shim_eval_js (handle, js);
        }

        /* A blob fetch may complete after the window is gone; the null
           handle drops it (the shim released the task on teardown). */
        private void deliver (void* token, uint8[] data, string mime) {
            if (handle != null) shim_finish_task (handle, token, data, mime);
        }

        private void fail (void* token) {
            if (handle != null) shim_fail_task (handle, token);
        }

        public void close_view () {
            if (handle != null) shim_close (handle);
        }
#else
        /* ============================================================
         *  View layer, GNOME: Adw.Window + WebKitGTK.
         * ============================================================ */

        private Adw.Window? win = null;
        private WebKit.WebView view;

        private void create_view (string title) {
            win = new Adw.Window ();
            win.title = title;
            win.default_width = 420;
            win.default_height = 640;

            var ucm = new WebKit.UserContentManager ();
            ucm.register_script_message_handler ("webxdc", (string) null);
            ucm.script_message_received["webxdc"].connect ((value) => {
                on_message (value.to_string ());
            });

            var ctx = new WebKit.WebContext ();
            ctx.register_uri_scheme ("webxdc", (req) => {
                serve.begin (req.get_path () ?? "", req);
            });
            var sec = ctx.get_security_manager ();
            sec.register_uri_scheme_as_secure ("webxdc");
            sec.register_uri_scheme_as_local ("webxdc");

            /* No cookies/cache on disk, and a blackhole proxy so any
               http(s) request an app may attempt dies before reaching the
               network. webxdc: URIs are served in-process and unaffected. */
            var session = new WebKit.NetworkSession.ephemeral ();
            session.set_proxy_settings (WebKit.NetworkProxyMode.CUSTOM,
                new WebKit.NetworkProxySettings ("socks5://127.0.0.1:1",
                                                 null));

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
            win.content = toolbar;
            win.close_request.connect (() => {
                win = null;
                on_view_closed ();
                return false;
            });
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

        public void present () {
            if (win != null) win.present ();
        }

        private void load_view (string uri) {
            view.load_uri (uri);
        }

        private void set_view_title (string title) {
            if (win != null) win.title = title;
        }

        private void eval_js (string js) {
            view.evaluate_javascript.begin (js, -1, null, null, null);
        }

        private void deliver (WebKit.URISchemeRequest token, uint8[] data,
                              string mime) {
            var stream = new MemoryInputStream.from_bytes (new Bytes (data));
            token.finish (stream, data.length, mime);
        }

        private void fail (WebKit.URISchemeRequest token) {
            token.finish_error (new IOError.NOT_FOUND ("webxdc blob"));
        }

        public void close_view () {
            if (win != null) win.close ();
        }
#endif
    }
}
