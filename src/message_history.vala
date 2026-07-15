namespace Dc {

    public class MessageHistory : Object {

        public static int find_id (Json.Array ids, int message_id) {
            for (uint i = 0; i < ids.get_length (); i++) {
                if ((int) ids.get_int_element (i) == message_id) return (int) i;
            }
            return -1;
        }

        public static uint earlier_batch_start (uint loaded_start,
                                                 uint target_index,
                                                 uint batch_size = 100) {
            if (target_index >= loaded_start) return loaded_start;
            uint start = loaded_start > batch_size
                ? loaded_start - batch_size : 0;
            return uint.max (start, target_index);
        }
    }
}
