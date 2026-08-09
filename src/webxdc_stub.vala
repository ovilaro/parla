/* No-op stand-in for webxdc.vala, compiled when -Dwebxdc=false (the
 * default) so the rest of the code links without WebKitGTK. */
namespace Dc.Webxdc {

    public const bool AVAILABLE = false;

    public void open (Gtk.Window? parent, RpcClient rpc, Message msg) { }

    public void status_update (int msg_id) { }

    public void instance_deleted (int msg_id) { }
}
