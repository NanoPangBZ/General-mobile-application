#include "com_host_bridge.h"
#include "com_host/com_host.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#define BRIDGE_CAPACITY 4096u
#define BRIDGE_QUEUE_SIZE 16u
#define LOG_QUEUE_SIZE 128u
#define LOG_LINE_CAPACITY 512u

typedef struct {
    uint32_t timestamp_ms;
    int32_t level;
    char text[LOG_LINE_CAPACITY];
} bridge_log_item_t;

typedef struct {
    bridge_log_item_t items[LOG_QUEUE_SIZE];
    uint16_t head, tail, count;
    uint32_t dropped;
} bridge_log_queue_t;

typedef struct {
    uint16_t size;
    uint16_t msg_id;
    uint8_t sender, seq, need_ack, is_ack;
    uint8_t data[BRIDGE_CAPACITY];
} bridge_item_t;

typedef struct {
    bridge_item_t items[BRIDGE_QUEUE_SIZE];
    uint8_t head, tail, count;
    uint32_t dropped;
} bridge_queue_t;

static uint64_t arena[16384];
static uint8_t scratch[BRIDGE_CAPACITY];
static bridge_queue_t output_queue, message_queue;
static bridge_queue_t input_queue;
static bridge_log_queue_t log_queue;
static bridge_item_t last_message;
static bridge_log_item_t last_log;
static com_host_handle_t host;
static com_host_port_handle_t port;
static int32_t init_result = -99;

void mobile_host_log(int32_t level, uint32_t timestamp_ms, const char* format, ...) {
    if (!format) return;
    if (log_queue.count == LOG_QUEUE_SIZE) {
        log_queue.dropped++;
        return;
    }
    bridge_log_item_t* item = &log_queue.items[log_queue.tail];
    item->level = level;
    item->timestamp_ms = timestamp_ms;
    va_list args;
    va_start(args, format);
    int written = vsnprintf(item->text, sizeof(item->text), format, args);
    va_end(args);
    if (written < 0) item->text[0] = '\0';
    else if ((size_t)written >= sizeof(item->text)) {
        item->text[sizeof(item->text) - 1u] = '\0';
    }
    log_queue.tail = (uint16_t)((log_queue.tail + 1u) % LOG_QUEUE_SIZE);
    log_queue.count++;
}

int32_t mobile_host_take_log(void) {
    if (!log_queue.count) return 0;
    last_log = log_queue.items[log_queue.head];
    log_queue.head = (uint16_t)((log_queue.head + 1u) % LOG_QUEUE_SIZE);
    log_queue.count--;
    return (int32_t)strlen(last_log.text) + 1;
}

int32_t mobile_host_log_level(void) { return last_log.level; }
uint32_t mobile_host_log_timestamp(void) { return last_log.timestamp_ms; }
uint32_t mobile_host_log_dropped(void) { return log_queue.dropped; }

static uint32_t clock_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint32_t)((uint64_t)now.tv_sec * 1000u + (uint32_t)now.tv_nsec / 1000000u);
}

static bridge_item_t* queue_push(bridge_queue_t* queue, uint32_t size) {
    if (size > BRIDGE_CAPACITY || queue->count == BRIDGE_QUEUE_SIZE) {
        queue->dropped++;
        return NULL;
    }
    bridge_item_t* item = &queue->items[queue->tail];
    item->size = (uint16_t)size;
    queue->tail = (uint8_t)((queue->tail + 1u) % BRIDGE_QUEUE_SIZE);
    queue->count++;
    return item;
}

static bridge_item_t* queue_front(bridge_queue_t* queue) {
    return queue->count ? &queue->items[queue->head] : NULL;
}

static void queue_pop(bridge_queue_t* queue) {
    queue->head = (uint8_t)((queue->head + 1u) % BRIDGE_QUEUE_SIZE);
    queue->count--;
}

static uint32_t write_bytes(void* ctx, const uint8_t* data, uint32_t size) {
    (void)ctx;
    bridge_item_t* item = queue_push(&output_queue, size);
    if (!item) return 0;
    memcpy(item->data, data, size);
    return size;
}

static uint32_t read_bytes(void* ctx, uint8_t* buffer, uint32_t size) {
    (void)ctx;
    bridge_item_t* item = queue_front(&input_queue);
    if (!item || !buffer || size == 0) return 0;
    uint32_t count = item->size < size ? item->size : size;
    memcpy(buffer, item->data, count);
    if (count == item->size) {
        queue_pop(&input_queue);
    } else {
        memmove(item->data, item->data + count, item->size - count);
        item->size = (uint16_t)(item->size - count);
    }
    return count;
}

static void on_message(com_host_handle_t owner, com_host_port_handle_t input,
                       com_host_id_t sender, com_host_msg_t* msg, uint8_t seq, void* ctx) {
    (void)owner; (void)input; (void)ctx;
    bridge_item_t* item = queue_push(&message_queue, msg->data_len);
    if (!item) return;
    item->msg_id = msg->msg_id;
    item->sender = sender;
    item->seq = seq;
    item->need_ack = msg->need_ack;
    item->is_ack = msg->is_ack;
    if (msg->data_len) memcpy(item->data, msg->data, msg->data_len);
}

int32_t mobile_host_init(void) {
    if (init_result != -99) return init_result;
    com_host_ll_depend_t dep = {
        .get_time_ms = clock_ms, .stack_buff = (uint8_t*)arena,
        .stack_buff_size = sizeof(arena), .stack_align = 8
    };
    com_host_init(&dep);
    com_host_desc_t desc = {.host_id = COM_HOST_ID_MOBOILE_APP};
    host = com_host_create(&desc);
    if (!host) return init_result = -1;
    com_host_port_desc_t port_desc = {
        .name = "mobile_transport", .attr = COM_HOST_PORT_ATTR_DEFAULT,
        .pack_buf_size = BRIDGE_CAPACITY, .unpack_buf_size = BRIDGE_CAPACITY,
        .write = write_bytes, .read = read_bytes
    };
    port = com_host_add_port(host, &port_desc);
    if (!port) return init_result = -2;
    if (com_host_add_route(host, COM_HOST_ID_MAIN_CONTROLLER, port) != 0) return init_result = -3;
    if (com_host_add_default_msg_handler(host, on_message, NULL) != 0) return init_result = -4;
    return init_result = 0;
}

uint8_t* mobile_host_buffer(void) { return scratch; }
uint32_t mobile_host_buffer_capacity(void) { return BRIDGE_CAPACITY; }

int32_t mobile_host_send(uint16_t msg_id, uint16_t size, uint8_t need_ack) {
    if (!port || size > BRIDGE_CAPACITY) return -1;
    com_host_msg_t msg = {0};
    msg.msg_id = msg_id;
    msg.data = size ? scratch : NULL;
    msg.data_len = size;
    msg.need_ack = need_ack ? 1 : 0;
    uint8_t seq = 0;
    int16_t result = com_host_send_msg(host, COM_HOST_ID_MAIN_CONTROLLER, &msg, &seq);
    return result == 0 ? seq : result;
}

int32_t mobile_host_send_ack(uint8_t sender, uint16_t msg_id, uint8_t seq, uint16_t size) {
    if (!port || size == 0 || size > BRIDGE_CAPACITY) return -1;
    com_host_msg_t original = {0};
    original.msg_id = msg_id;
    return com_host_send_ack(host, port, sender, &original, scratch, size, seq);
}

int32_t mobile_host_feed(uint32_t size) {
    if (!port || size > BRIDGE_CAPACITY) return -1;
    if (size == 0) return 0;
    bridge_item_t* item = queue_push(&input_queue, size);
    if (!item) return -2;
    memcpy(item->data, scratch, size);
    return 0;
}

void mobile_host_run(void) {
    if (host) com_host_run(host);
}

int32_t mobile_host_take_output(void) {
    bridge_item_t* item = queue_front(&output_queue);
    if (!item) return 0;
    memcpy(scratch, item->data, item->size);
    int32_t size = item->size;
    queue_pop(&output_queue);
    return size;
}

int32_t mobile_host_take_message(void) {
    bridge_item_t* item = queue_front(&message_queue);
    if (!item) return 0;
    memcpy(&last_message, item, sizeof(last_message));
    if (item->size) memcpy(scratch, item->data, item->size);
    queue_pop(&message_queue);
    return (int32_t)last_message.size + 1;
}

uint16_t mobile_host_message_id(void) { return last_message.msg_id; }
uint8_t mobile_host_message_sender(void) { return last_message.sender; }
uint8_t mobile_host_message_seq(void) { return last_message.seq; }
uint8_t mobile_host_message_need_ack(void) { return last_message.need_ack; }
uint8_t mobile_host_message_is_ack(void) { return last_message.is_ack; }
uint32_t mobile_host_dropped_output(void) { return output_queue.dropped; }
uint32_t mobile_host_dropped_messages(void) { return message_queue.dropped; }
uint32_t mobile_host_dropped_input(void) { return input_queue.dropped; }
