namespace Dc {

    public class RpcParsers {

        public static Contact parse_contact (int contact_id, Json.Object obj) {
            var c = new Contact ();
            c.id = contact_id;
            c.display_name = json_str (obj, "displayName") ?? "";
            c.address = json_str (obj, "address") ?? "";
            c.profile_image = json_str (obj, "profileImage");
            c.is_verified = json_bool (obj, "isVerified");
            return c;
        }

        public static Message parse_message (Json.Object obj,
                                             string? self_email = null) {
            var msg = new Message ();
            msg.id = (int) json_int (obj, "id");
            msg.chat_id = (int) json_int (obj, "chatId");
            msg.text = json_str (obj, "text");
            msg.timestamp = json_int (obj, "timestamp");
            msg.is_info = json_bool (obj, "isInfo");
            msg.is_forwarded = json_bool (obj, "isForwarded");
            msg.override_sender_name = json_str (obj, "overrideSenderName");

            msg.file_path = json_str (obj, "file");
            msg.file_name = json_str (obj, "fileName");
            msg.file_mime = json_str (obj, "fileMime");
            msg.file_bytes = (int) json_int (obj, "fileBytes");
            msg.view_type = json_str (obj, "viewType");
            msg.state = (int) json_int (obj, "state");

            if (obj.has_member ("sender") && !obj.get_member ("sender").is_null ()) {
                var sender = obj.get_object_member ("sender");
                msg.sender_address = json_str (sender, "address");
                msg.sender_name = json_str (sender, "displayName")
                    ?? json_str (sender, "name");
            }

            if (self_email != null && msg.sender_address != null) {
                msg.is_outgoing = msg.sender_address.down () == self_email.down ();
            }
            if (obj.has_member ("fromId") && obj.get_int_member ("fromId") == 1) {
                msg.is_outgoing = true;
            }

            parse_reactions (obj, msg);
            parse_quote (obj, msg);
            return msg;
        }

        public static ChatEntry parse_chat_item (int chat_id, Json.Object obj) {
            var entry = new ChatEntry ();
            entry.id = chat_id;
            entry.name = json_str (obj, "name") ?? "";

            var s1 = json_str (obj, "summaryText1");
            if (s1 != null && s1.length > 0) entry.summary_prefix = s1;

            var s2 = json_str (obj, "summaryText2");
            if (s2 != null && s2.length > 0) entry.last_message = s2;

            if (entry.last_message == null) {
                entry.last_message = json_str (obj, "lastMessageText");
            }

            entry.unread_count = (int) json_int (obj, "freshMessageCounter");
            entry.timestamp = json_int (obj, "lastMessageTimestamp");
            entry.avatar_path = json_str (obj, "avatarPath");
            entry.is_muted = json_bool (obj, "isMuted");
            entry.is_contact_request = json_bool (obj, "isContactRequest");
            entry.is_archived = json_bool (obj, "isArchived");
            entry.is_pinned = json_bool (obj, "isPinned");
            return entry;
        }

        private static void parse_reactions (Json.Object obj, Message msg) {
            if (!obj.has_member ("reactions") || obj.get_member ("reactions").is_null ())
                return;

            var reactions_obj = obj.get_object_member ("reactions");
            if (reactions_obj == null ||
                !reactions_obj.has_member ("reactionsByContact") ||
                reactions_obj.get_member ("reactionsByContact").is_null ())
                return;

            var by_contact = reactions_obj.get_object_member ("reactionsByContact");
            string[] r_emojis = {};
            int[] r_counts = {};
            string[] my_emojis = {};

            var members = by_contact.get_members ();
            foreach (unowned string cid in members) {
                var node = by_contact.get_member (cid);
                if (node.get_node_type () != Json.NodeType.ARRAY) continue;
                var arr = node.get_array ();
                bool is_self = (cid == "1");
                for (uint j = 0; j < arr.get_length (); j++) {
                    string emoji = arr.get_string_element (j);
                    if (is_self) my_emojis += emoji;
                    int found = -1;
                    for (int k = 0; k < r_emojis.length; k++) {
                        if (r_emojis[k] == emoji) {
                            found = k;
                            break;
                        }
                    }
                    if (found >= 0) {
                        r_counts[found] = r_counts[found] + 1;
                    } else {
                        r_emojis += emoji;
                        r_counts += 1;
                    }
                }
            }

            if (my_emojis.length > 0) {
                msg.my_reactions = string.joinv (",", my_emojis);
            }

            if (r_emojis.length == 0) return;

            var sb = new StringBuilder ();
            for (int k = 0; k < r_emojis.length; k++) {
                if (sb.len > 0) sb.append (",");
                sb.append_printf ("%s:%d", r_emojis[k], r_counts[k]);
            }
            msg.reactions = sb.str;
        }

        private static void parse_quote (Json.Object obj, Message msg) {
            if (!obj.has_member ("quote") || obj.get_member ("quote").is_null ())
                return;

            var quote = obj.get_object_member ("quote");
            msg.quote_text = json_str (quote, "text");
            msg.quote_sender_name = json_str (quote, "authorDisplayName");
            msg.quote_msg_id = (int) json_int (quote, "messageId");
        }
    }
}
