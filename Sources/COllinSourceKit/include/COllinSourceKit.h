// COllinSourceKit: the slice of the Swift toolchain's SourceKit C interface that
// OllinRuntime's code completion reaches at runtime.
//
// The toolchain ships the service as a framework with no header, so these are
// Ollin's own declarations of the parts it calls: the opaque handles, the
// one value type that crosses by value (a response variant is three words, and
// Swift can only pass a C struct by value through a C function pointer when the
// struct is declared in C), and a typedef per entry point. Nothing is linked at
// build time; `CodeCompleter` finds the framework beside `swiftc`, opens it with
// `dlopen`, and binds each entry point by name with `dlsym`, so a machine whose
// toolchain lacks the service loses completion and nothing else.
#ifndef COLLIN_SOURCEKIT_H
#define COLLIN_SOURCEKIT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// A request object, a response, and an interned name, all opaque.
typedef void *osk_object_t;
typedef void *osk_response_t;
typedef void *osk_uid_t;

/// A value inside a response. Passed and returned by value: three words the
/// service owns, valid until the response is disposed.
typedef struct {
    uint64_t data[3];
} osk_variant_t;

/// What a variant holds, as `osk_variant_get_type_t` reports it.
enum {
    OSK_VARIANT_NULL = 0,
    OSK_VARIANT_DICTIONARY = 1,
    OSK_VARIANT_ARRAY = 2,
    OSK_VARIANT_INT64 = 3,
    OSK_VARIANT_STRING = 4,
    OSK_VARIANT_UID = 5,
    OSK_VARIANT_BOOL = 6,
    OSK_VARIANT_DOUBLE = 7,
};

// The index that appends to a request array is every bit set, `(size_t)-1`;
// Swift imports `size_t` as `Int`, so the caller spells it `-1`.

// The entry points, named after the symbols they bind to with the
// `sourcekitd_` prefix dropped: `osk_initialize_t` is `sourcekitd_initialize`.
typedef void (*osk_initialize_t)(void);
typedef void (*osk_shutdown_t)(void);
typedef osk_uid_t (*osk_uid_get_from_cstr_t)(const char *string);
typedef const char *(*osk_uid_get_string_ptr_t)(osk_uid_t uid);

typedef osk_object_t (*osk_request_dictionary_create_t)(const osk_uid_t *keys, const osk_object_t *values, size_t count);
typedef void (*osk_request_dictionary_set_string_t)(osk_object_t dict, osk_uid_t key, const char *string);
typedef void (*osk_request_dictionary_set_int64_t)(osk_object_t dict, osk_uid_t key, int64_t value);
typedef void (*osk_request_dictionary_set_uid_t)(osk_object_t dict, osk_uid_t key, osk_uid_t uid);
typedef void (*osk_request_dictionary_set_value_t)(osk_object_t dict, osk_uid_t key, osk_object_t value);
typedef osk_object_t (*osk_request_array_create_t)(const osk_object_t *objects, size_t count);
typedef void (*osk_request_array_set_string_t)(osk_object_t array, size_t index, const char *string);
typedef void (*osk_request_release_t)(osk_object_t object);

typedef osk_response_t (*osk_send_request_sync_t)(osk_object_t request);
typedef void (*osk_response_dispose_t)(osk_response_t response);
typedef bool (*osk_response_is_error_t)(osk_response_t response);
typedef const char *(*osk_response_error_get_description_t)(osk_response_t response);
typedef osk_variant_t (*osk_response_get_value_t)(osk_response_t response);

typedef int (*osk_variant_get_type_t)(osk_variant_t variant);
typedef osk_variant_t (*osk_variant_dictionary_get_value_t)(osk_variant_t dict, osk_uid_t key);
typedef const char *(*osk_variant_dictionary_get_string_t)(osk_variant_t dict, osk_uid_t key);
typedef int64_t (*osk_variant_dictionary_get_int64_t)(osk_variant_t dict, osk_uid_t key);
typedef bool (*osk_variant_dictionary_get_bool_t)(osk_variant_t dict, osk_uid_t key);
typedef osk_uid_t (*osk_variant_dictionary_get_uid_t)(osk_variant_t dict, osk_uid_t key);
typedef size_t (*osk_variant_array_get_count_t)(osk_variant_t array);
typedef osk_variant_t (*osk_variant_array_get_value_t)(osk_variant_t array, size_t index);

#endif
