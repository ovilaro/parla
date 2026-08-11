namespace Dc.SubprocessUtil {
    /* Vala 0.56 loses the nested const qualifiers used by GLib's strv
       APIs. This binding makes the generated C conversion explicit. */
    [CCode (cname = "g_subprocess_launcher_spawnv",
            cheader_filename = "gio/gio.h")]
    private extern GLib.Subprocess launcher_spawnv (
        GLib.SubprocessLauncher launcher,
        [CCode (array_length = false, array_null_terminated = true,
                type = "const gchar * const *")]
        string[] argv) throws GLib.Error;

    public GLib.Subprocess spawnv (GLib.SubprocessLauncher launcher,
                                   string[] argv) throws GLib.Error {
        return launcher_spawnv (launcher, argv);
    }
}
