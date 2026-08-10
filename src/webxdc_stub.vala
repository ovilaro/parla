/* No-op stand-in for webxdc.vala, compiled when -Dwebxdc=false (the
 * default) so the rest of the code links without WebKitGTK. */
namespace Dc.Webxdc {

    public const bool AVAILABLE = false;

    public class CardInfo {
        public string? name;
        public Gdk.Texture? icon;
    }

    public void setup (RpcClient rpc, SettingsManager settings) { }

    public bool enabled () { return false; }

    public async CardInfo card_info (int msg_id) { return new CardInfo (); }

    public void open (Gtk.Window? parent, RpcClient rpc, Message msg) { }

    public void status_update (int msg_id) { }

    public void instance_deleted (int msg_id) { }
}
