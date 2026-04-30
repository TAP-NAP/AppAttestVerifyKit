#ifndef APP_ATTEST_VERIFIER_FFI_H
#define APP_ATTEST_VERIFIER_FFI_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AppAttestVerifierFFIBuffer {
    uint8_t *ptr;
    uintptr_t len;
} AppAttestVerifierFFIBuffer;

AppAttestVerifierFFIBuffer app_attest_verifier_verify_attestation(
    const uint8_t *request_json_ptr,
    uintptr_t request_json_len
);

AppAttestVerifierFFIBuffer app_attest_verifier_verify_assertion(
    const uint8_t *request_json_ptr,
    uintptr_t request_json_len
);

void app_attest_verifier_free_buffer(AppAttestVerifierFFIBuffer buffer);

#ifdef __cplusplus
}
#endif

#endif
