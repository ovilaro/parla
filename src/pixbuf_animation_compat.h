#ifndef PARLA_PIXBUF_ANIMATION_COMPAT_H
#define PARLA_PIXBUF_ANIMATION_COMPAT_H

#include <gdk-pixbuf/gdk-pixbuf.h>

/* GdkPixbuf 2.44 deprecated the animation API without a replacement. */
G_GNUC_BEGIN_IGNORE_DEPRECATIONS

static inline GdkPixbufAnimation *
parla_pixbuf_animation_load (const gchar *f, GError **e) { return gdk_pixbuf_animation_new_from_file (f, e); }
static inline GdkPixbuf *
parla_pixbuf_animation_get_static_image (GdkPixbufAnimation *a) { return gdk_pixbuf_animation_get_static_image (a); }
static inline GdkPixbufAnimationIter *
parla_pixbuf_animation_get_iter (GdkPixbufAnimation *a) { return gdk_pixbuf_animation_get_iter (a, NULL); }
static inline GdkPixbuf *
parla_pixbuf_animation_iter_get_pixbuf (GdkPixbufAnimationIter *i) { return gdk_pixbuf_animation_iter_get_pixbuf (i); }
static inline gint
parla_pixbuf_animation_iter_get_delay_time (GdkPixbufAnimationIter *i) { return gdk_pixbuf_animation_iter_get_delay_time (i); }
static inline gboolean
parla_pixbuf_animation_iter_advance (GdkPixbufAnimationIter *i) { return gdk_pixbuf_animation_iter_advance (i, NULL); }
static inline gboolean
parla_pixbuf_animation_is_static_image (GdkPixbufAnimation *a) { return gdk_pixbuf_animation_is_static_image (a); }
static inline gint
parla_pixbuf_animation_get_width (GdkPixbufAnimation *a) { return gdk_pixbuf_animation_get_width (a); }
static inline gint
parla_pixbuf_animation_get_height (GdkPixbufAnimation *a) { return gdk_pixbuf_animation_get_height (a); }

G_GNUC_END_IGNORE_DEPRECATIONS

#endif
