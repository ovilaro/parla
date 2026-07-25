namespace Dc {

    /** Static first frame of an image file, downscaled to fit max_px in
        both dimensions (never upscaled). PixbufAnimation copes with
        animated GIF/WebP, where Pixbuf.from_file_at_scale refuses
        multi-frame files (stickers, typically). */
    internal Gdk.Pixbuf scaled_frame_from_file (string path,
                                                int max_px) throws Error {
        var anim = new Gdk.PixbufAnimation.from_file (path);
        Gdk.Pixbuf frame = anim.get_static_image ();
        double scale = double.min (1.0, double.min (
            (double) max_px / frame.width,
            (double) max_px / frame.height));
        if (scale < 1.0) {
            frame = frame.scale_simple (
                int.max (1, (int) (frame.width * scale + 0.5)),
                int.max (1, (int) (frame.height * scale + 0.5)),
                Gdk.InterpType.BILINEAR);
        }
        return frame;
    }

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
