namespace Dc {

    public bool gtk_emoji_chooser_available () {
        var source = SettingsSchemaSource.get_default ();
        if (source == null) return false;

        var schema = source.lookup ("org.gtk.gtk4.Settings.EmojiChooser", true);
        if (schema != null) return true;

        schema = source.lookup ("org.gtk.Settings.EmojiChooser", true);
        return schema != null;
    }

    public Gtk.EmojiChooser? create_emoji_chooser () {
        if (!gtk_emoji_chooser_available ()) return null;
        return new Gtk.EmojiChooser ();
    }
}
