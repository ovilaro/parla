namespace Dc {

    namespace PixbufAnimationCompat {
        [CCode (cname = "parla_pixbuf_animation_load",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern Gdk.PixbufAnimation load (string path) throws Error;

        [CCode (cname = "parla_pixbuf_animation_get_static_image",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern unowned Gdk.Pixbuf get_static_image (
            Gdk.PixbufAnimation animation);

        [CCode (cname = "parla_pixbuf_animation_get_iter",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern Gdk.PixbufAnimationIter get_iter (
            Gdk.PixbufAnimation animation);

        [CCode (cname = "parla_pixbuf_animation_iter_get_pixbuf",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern unowned Gdk.Pixbuf iter_get_pixbuf (
            Gdk.PixbufAnimationIter iter);

        [CCode (cname = "parla_pixbuf_animation_iter_get_delay_time",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern int iter_get_delay_time (Gdk.PixbufAnimationIter iter);

        [CCode (cname = "parla_pixbuf_animation_iter_advance",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern bool iter_advance (Gdk.PixbufAnimationIter iter);

        [CCode (cname = "parla_pixbuf_animation_is_static_image",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern bool is_static_image (Gdk.PixbufAnimation animation);

        [CCode (cname = "parla_pixbuf_animation_get_width",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern int get_width (Gdk.PixbufAnimation animation);

        [CCode (cname = "parla_pixbuf_animation_get_height",
                cheader_filename = "pixbuf_animation_compat.h")]
        internal extern int get_height (Gdk.PixbufAnimation animation);
    }

    /** Static first frame of an image file, downscaled to fit max_px in
        both dimensions (never upscaled). PixbufAnimation copes with
        animated GIF/WebP, where Pixbuf.from_file_at_scale refuses
        multi-frame files (stickers, typically). */
    internal Gdk.Pixbuf scaled_frame_from_file (string path,
                                                int max_px) throws Error {
        var anim = PixbufAnimationCompat.load (path);
        Gdk.Pixbuf frame = PixbufAnimationCompat.get_static_image (anim);
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
