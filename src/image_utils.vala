namespace Dc {

    internal Gdk.Texture texture_from_pixbuf (Gdk.Pixbuf pixbuf) {
        var format = pixbuf.has_alpha
            ? Gdk.MemoryFormat.R8G8B8A8
            : Gdk.MemoryFormat.R8G8B8;

        return new Gdk.MemoryTexture (
            pixbuf.width,
            pixbuf.height,
            format,
            pixbuf.read_pixel_bytes (),
            pixbuf.rowstride);
    }
}
