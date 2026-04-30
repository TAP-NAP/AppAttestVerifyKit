use apple_app_attest_attestation::{
    parse_and_verify_assertion, parse_and_verify_attestation_with_options, AppAttestEnvironment,
    AssertionCounterPolicy, AssertionError, AssertionVerificationContext, AttestationError,
    AttestationVerificationContext, VerificationOptions,
};
use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::slice;
use std::time::{Duration, SystemTime};

#[repr(C)]
pub struct AppAttestVerifierFFIBuffer {
    ptr: *mut u8,
    len: usize,
}

#[derive(Debug, Deserialize)]
struct AttestationRequest {
    attestation_object_base64: String,
    root_anchor_base64: String,
    client_data_hash_base64: String,
    team_id: String,
    bundle_id: String,
    environment: EnvironmentRequest,
    input_check: bool,
    verification_time_unix_seconds: Option<u64>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum EnvironmentRequest {
    Production,
    Development,
}

impl From<EnvironmentRequest> for AppAttestEnvironment {
    fn from(value: EnvironmentRequest) -> Self {
        match value {
            EnvironmentRequest::Production => Self::Production,
            EnvironmentRequest::Development => Self::Development,
        }
    }
}

#[derive(Debug, Deserialize)]
struct AssertionRequest {
    assertion_object_base64: String,
    client_data_base64: String,
    public_key_x962_base64: String,
    team_id: String,
    bundle_id: String,
    counter_policy: CounterPolicyRequest,
    previous_counter: Option<u32>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum CounterPolicyRequest {
    Strict,
    Positive,
    Unchecked,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
struct FFIResponse<T, E> {
    ok: bool,
    value: Option<T>,
    error: Option<E>,
}

#[derive(Debug, Serialize)]
struct StructuredFFIError {
    validation_stage: String,
    error_code: String,
    message: String,
}

#[no_mangle]
pub extern "C" fn app_attest_verifier_verify_attestation(
    request_json_ptr: *const u8,
    request_json_len: usize,
) -> AppAttestVerifierFFIBuffer {
    let output = match read_json(request_json_ptr, request_json_len) {
        Ok(bytes) => verify_attestation_json(&bytes),
        Err(error) => encode_error(error),
    };

    into_buffer(output)
}

#[no_mangle]
pub extern "C" fn app_attest_verifier_verify_assertion(
    request_json_ptr: *const u8,
    request_json_len: usize,
) -> AppAttestVerifierFFIBuffer {
    let output = match read_json(request_json_ptr, request_json_len) {
        Ok(bytes) => verify_assertion_json(&bytes),
        Err(error) => encode_error(error),
    };

    into_buffer(output)
}

#[no_mangle]
pub extern "C" fn app_attest_verifier_free_buffer(buffer: AppAttestVerifierFFIBuffer) {
    if buffer.ptr.is_null() || buffer.len == 0 {
        return;
    }

    unsafe {
        drop(Vec::from_raw_parts(buffer.ptr, buffer.len, buffer.len));
    }
}

fn read_json(ptr: *const u8, len: usize) -> Result<Vec<u8>, StructuredFFIError> {
    if ptr.is_null() {
        return Err(StructuredFFIError {
            validation_stage: "input_prefilter".to_owned(),
            error_code: "INPUT_INVALID".to_owned(),
            message: "request JSON pointer was null".to_owned(),
        });
    }

    let bytes = unsafe { slice::from_raw_parts(ptr, len) };
    Ok(bytes.to_vec())
}

fn verify_attestation_json(request_json: &[u8]) -> Vec<u8> {
    let request: AttestationRequest = match serde_json::from_slice(request_json) {
        Ok(request) => request,
        Err(error) => return encode_error(ffi_error("input_prefilter", "INPUT_INVALID", error)),
    };

    let attestation_object = match decode_base64(
        &request.attestation_object_base64,
        "attestation_object_base64",
        "ATTESTATION_OBJECT_CBOR_INVALID",
    ) {
        Ok(bytes) => bytes,
        Err(error) => return encode_error(error),
    };

    let root_anchor = match decode_base64(
        &request.root_anchor_base64,
        "root_anchor_base64",
        "ROOT_ANCHOR_INVALID",
    ) {
        Ok(bytes) => bytes,
        Err(error) => return encode_error(error),
    };

    let client_data_hash = match decode_base64(
        &request.client_data_hash_base64,
        "client_data_hash_base64",
        "INPUT_INVALID",
    ) {
        Ok(bytes) => bytes,
        Err(error) => return encode_error(error),
    };

    let context = AttestationVerificationContext {
        client_data_hash,
        team_id: request.team_id,
        bundle_id: request.bundle_id,
        environment: request.environment.into(),
    };
    let options = VerificationOptions {
        prefilter_enabled: request.input_check,
        verification_time: request
            .verification_time_unix_seconds
            .map(|seconds| SystemTime::UNIX_EPOCH + Duration::from_secs(seconds)),
        ..VerificationOptions::default()
    };

    match parse_and_verify_attestation_with_options(
        &attestation_object,
        &root_anchor,
        &context,
        &options,
    ) {
        Ok(success) => encode_success(success),
        Err(error) => encode_error(attestation_error(error)),
    }
}

fn verify_assertion_json(request_json: &[u8]) -> Vec<u8> {
    let request: AssertionRequest = match serde_json::from_slice(request_json) {
        Ok(request) => request,
        Err(error) => return encode_error(ffi_error("input_prefilter", "INPUT_INVALID", error)),
    };

    let assertion_object = match decode_base64(
        &request.assertion_object_base64,
        "assertion_object_base64",
        "ASSERTION_OBJECT_CBOR_INVALID",
    ) {
        Ok(bytes) => bytes,
        Err(error) => return encode_error(error),
    };

    let client_data = match decode_base64(
        &request.client_data_base64,
        "client_data_base64",
        "INPUT_INVALID",
    ) {
        Ok(bytes) => bytes,
        Err(error) => return encode_error(error),
    };

    let public_key_x962 = match decode_base64(
        &request.public_key_x962_base64,
        "public_key_x962_base64",
        "PUBLIC_KEY_INVALID",
    ) {
        Ok(bytes) => bytes,
        Err(error) => return encode_error(error),
    };

    let counter_policy = match build_counter_policy(request.counter_policy, request.previous_counter)
    {
        Ok(policy) => policy,
        Err(error) => return encode_error(error),
    };

    let context = AssertionVerificationContext {
        client_data,
        public_key_x962,
        team_id: request.team_id,
        bundle_id: request.bundle_id,
        counter_policy,
    };

    match parse_and_verify_assertion(&assertion_object, &context) {
        Ok(success) => encode_success(success),
        Err(error) => encode_error(assertion_error(error)),
    }
}

fn build_counter_policy(
    request: CounterPolicyRequest,
    previous_counter: Option<u32>,
) -> Result<AssertionCounterPolicy, StructuredFFIError> {
    match request {
        CounterPolicyRequest::Strict => {
            let previous_counter = previous_counter.ok_or_else(|| {
                ffi_error(
                    "input_prefilter",
                    "COUNTER_INVALID",
                    "--counter-policy strict requires previous_counter",
                )
            })?;
            Ok(AssertionCounterPolicy::StrictGreaterThan { previous_counter })
        }
        CounterPolicyRequest::Positive => Ok(AssertionCounterPolicy::RequirePositive),
        CounterPolicyRequest::Unchecked => Ok(AssertionCounterPolicy::Unchecked),
    }
}

fn decode_base64(
    encoded: &str,
    field: &str,
    code: &str,
) -> Result<Vec<u8>, StructuredFFIError> {
    STANDARD.decode(encoded).map_err(|error| {
        ffi_error(
            "input_prefilter",
            code,
            format!("failed to decode {field}: {error}"),
        )
    })
}

fn encode_success<T: Serialize>(value: T) -> Vec<u8> {
    serde_json::to_vec(&FFIResponse {
        ok: true,
        value: Some(value),
        error: Option::<StructuredFFIError>::None,
    })
    .expect("FFI success JSON serialization must not fail")
}

fn encode_error(error: StructuredFFIError) -> Vec<u8> {
    serde_json::to_vec(&FFIResponse::<serde_json::Value, _> {
        ok: false,
        value: None,
        error: Some(error),
    })
    .expect("FFI error JSON serialization must not fail")
}

fn into_buffer(mut bytes: Vec<u8>) -> AppAttestVerifierFFIBuffer {
    let buffer = AppAttestVerifierFFIBuffer {
        ptr: bytes.as_mut_ptr(),
        len: bytes.len(),
    };
    std::mem::forget(bytes);
    buffer
}

fn attestation_error(error: AttestationError) -> StructuredFFIError {
    StructuredFFIError {
        validation_stage: error.validation_stage.as_str().to_owned(),
        error_code: error.error_code.as_str().to_owned(),
        message: error.message.into_owned(),
    }
}

fn assertion_error(error: AssertionError) -> StructuredFFIError {
    StructuredFFIError {
        validation_stage: error.validation_stage.as_str().to_owned(),
        error_code: error.error_code.as_str().to_owned(),
        message: error.message.into_owned(),
    }
}

fn ffi_error(
    validation_stage: impl Into<String>,
    error_code: impl Into<String>,
    message: impl ToString,
) -> StructuredFFIError {
    StructuredFFIError {
        validation_stage: validation_stage.into(),
        error_code: error_code.into(),
        message: message.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::fs;
    use std::path::PathBuf;

    const SAMPLE_VERIFICATION_TIME_UNIX: u64 = 1_713_456_894;

    #[test]
    fn attestation_ffi_returns_success_json() {
        let fixtures = fixture_root();
        let request = AttestationRequestForTest {
            attestation_object_base64: STANDARD
                .encode(fs::read(fixtures.join("positive/apple_attestation_object.cbor")).unwrap()),
            root_anchor_base64: STANDARD.encode(
                fs::read(fixtures.join("anchors/apple_app_attestation_root_ca.pem")).unwrap(),
            ),
            client_data_hash_base64: STANDARD.encode(b"test_server_challenge"),
            team_id: "0352187391".to_owned(),
            bundle_id: "com.apple.example_app_attest".to_owned(),
            environment: "production".to_owned(),
            input_check: true,
            verification_time_unix_seconds: Some(SAMPLE_VERIFICATION_TIME_UNIX),
        };

        let response = verify_attestation_json(&serde_json::to_vec(&request).unwrap());
        let value: Value = serde_json::from_slice(&response).unwrap();

        assert_eq!(value["ok"], true);
        assert!(value["value"]["receipt_raw"].is_string());
        assert!(value["value"]["first_certificate_values"]["public_key_x962"].is_string());
    }

    #[test]
    fn assertion_ffi_returns_structured_error_json() {
        let request = AssertionRequestForTest {
            assertion_object_base64: STANDARD.encode(b"not-cbor"),
            client_data_base64: STANDARD.encode(b"client-data"),
            public_key_x962_base64: STANDARD.encode(b"not-a-key"),
            team_id: "TEAMID1234".to_owned(),
            bundle_id: "com.example.app".to_owned(),
            counter_policy: "unchecked".to_owned(),
            previous_counter: None,
        };

        let response = verify_assertion_json(&serde_json::to_vec(&request).unwrap());
        let value: Value = serde_json::from_slice(&response).unwrap();

        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["validation_stage"], "parse_assertion_object");
        assert_eq!(value["error"]["error_code"], "ASSERTION_OBJECT_CBOR_INVALID");
    }

    #[derive(Serialize)]
    struct AttestationRequestForTest {
        attestation_object_base64: String,
        root_anchor_base64: String,
        client_data_hash_base64: String,
        team_id: String,
        bundle_id: String,
        environment: String,
        input_check: bool,
        verification_time_unix_seconds: Option<u64>,
    }

    #[derive(Serialize)]
    struct AssertionRequestForTest {
        assertion_object_base64: String,
        client_data_base64: String,
        public_key_x962_base64: String,
        team_id: String,
        bundle_id: String,
        counter_policy: String,
        previous_counter: Option<u32>,
    }

    fn fixture_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../tests/fixtures")
            .canonicalize()
            .expect("upstream fixtures must exist")
    }
}
