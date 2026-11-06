#pragma once
#include <stdint.h>

#if defined(__GNUC__)
#define MOBILE_HOST_EXPORT __attribute__((visibility("default"), used))
#else
#define MOBILE_HOST_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

// All functions must be called on one Dart isolate. The host lives for the process lifetime.
MOBILE_HOST_EXPORT int32_t mobile_host_init(void);
MOBILE_HOST_EXPORT uint8_t* mobile_host_buffer(void);
MOBILE_HOST_EXPORT uint32_t mobile_host_buffer_capacity(void);
MOBILE_HOST_EXPORT int32_t mobile_host_send(uint16_t msg_id, uint16_t size, uint8_t need_ack);
MOBILE_HOST_EXPORT int32_t mobile_host_send_ack(uint8_t sender, uint16_t msg_id, uint8_t seq, uint16_t size);
MOBILE_HOST_EXPORT int32_t mobile_host_feed(uint32_t size);
MOBILE_HOST_EXPORT void mobile_host_run(void);
MOBILE_HOST_EXPORT int32_t mobile_host_take_output(void);
// Returns payload length + 1, or 0 when no message is queued.
MOBILE_HOST_EXPORT int32_t mobile_host_take_message(void);
MOBILE_HOST_EXPORT uint16_t mobile_host_message_id(void);
MOBILE_HOST_EXPORT uint8_t mobile_host_message_sender(void);
MOBILE_HOST_EXPORT uint8_t mobile_host_message_seq(void);
MOBILE_HOST_EXPORT uint8_t mobile_host_message_need_ack(void);
MOBILE_HOST_EXPORT uint8_t mobile_host_message_is_ack(void);
MOBILE_HOST_EXPORT uint32_t mobile_host_dropped_output(void);
MOBILE_HOST_EXPORT uint32_t mobile_host_dropped_messages(void);
MOBILE_HOST_EXPORT uint32_t mobile_host_dropped_input(void);
// Queue a formatted com_host log line for delivery to the Dart application log.
MOBILE_HOST_EXPORT void mobile_host_log(int32_t level, uint32_t timestamp_ms, const char* format, ...);
MOBILE_HOST_EXPORT int32_t mobile_host_take_log(void);
MOBILE_HOST_EXPORT int32_t mobile_host_log_level(void);
MOBILE_HOST_EXPORT uint32_t mobile_host_log_timestamp(void);
MOBILE_HOST_EXPORT uint32_t mobile_host_log_dropped(void);

#ifdef __cplusplus
}
#endif
