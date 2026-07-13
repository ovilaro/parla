namespace Dc {

    /** Semantic Delta Chat view types for outgoing attachments. */
    public class AttachmentTypes : Object {

        /**
         * Keep outgoing classification aligned with Message.is_sticker_file():
         * these formats are presented by Parla as stickers, so they must also
         * be announced as stickers to other Delta Chat clients.
         */
        public static string? infer_outgoing_view_type (
                string? file_path, string? file_name = null) {
            if (has_sticker_extension (file_path)
                || has_sticker_extension (file_name)) {
                return "Sticker";
            }
            return null;
        }

        private static bool has_sticker_extension (string? value) {
            if (value == null) return false;
            string lower = value.down ();
            return lower.has_suffix (".gif")
                || lower.has_suffix (".webp")
                || lower.has_suffix (".webm");
        }
    }
}
