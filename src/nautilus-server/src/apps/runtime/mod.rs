use axum::extract::State;
use axum::Json;
use crate::common::{to_signed_response, IntentMessage, IntentScope, ProcessDataRequest, ProcessedDataResponse};
use crate::{AppState, EnclaveError};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::Command;
use uuid::Uuid;
use walrus_rs::WalrusClient;

/// ==== Nautilus-compatible app module ====
/// This module exposes a single `process_data` handler that can be wired
/// into the Nautilus server. It reads a Walrus blob (containing code),
/// auto-detects language (JS/TS or Python), executes it with the provided
/// JSON payload, and returns a signed response.

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Language {
    Js,
    Ts,
    Py,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct BlobExecutionRequest {
    pub blob_id: String,
    pub payload: Value,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RuntimeResult {
    pub program_id: String,
    pub code_hash: String,
    pub input_hash: String,
    pub output: Value,
}

/// Core entrypoint called by Nautilus at `/process_data`.
pub async fn process_data(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ProcessDataRequest<BlobExecutionRequest>>,
) -> Result<Json<ProcessedDataResponse<IntentMessage<RuntimeResult>>>, EnclaveError> {
    // Build Walrus client from env or defaults.
    let aggregator_url = std::env::var("AGGREGATOR")
        .unwrap_or_else(|_| "https://aggregator.testnet.walrus.atalma.io".to_string());
    let publisher_url = std::env::var("PUBLISHER")
        .unwrap_or_else(|_| "https://publisher.walrus-01.tududes.com".to_string());

    let walrus_client = WalrusClient::new(&aggregator_url, &publisher_url)
        .map_err(|e| EnclaveError::GenericError(format!("Failed to create WalrusClient: {}", e)))?;

    // Read blob bytes by id.
    let code_bytes = walrus_client
        .read_blob_by_id(&request.payload.blob_id)
        .await
        .map_err(|e| EnclaveError::GenericError(format!(
            "Failed to read walrus blob {}: {}",
            request.payload.blob_id, e
        )))?;

    // Blob may be raw code or JSON with a `code` field.
    let blob_text = String::from_utf8(code_bytes).map_err(|e| {
        EnclaveError::GenericError(format!("Invalid UTF-8 in walrus blob: {}", e))
    })?;

    let code = if blob_text.trim_start().starts_with('{') {
        let v: Value = serde_json::from_str(&blob_text).map_err(|e| {
            EnclaveError::GenericError(format!("Invalid JSON blob: {}", e))
        })?;
        v.get("code")
            .and_then(|c| c.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| EnclaveError::GenericError("JSON blob missing `code` field".to_string()))?
    } else {
        blob_text
    };

    // Detect language and compute hashes.
    let lang = detect_language(&code);
    let code_hash = sha256_hex(&code);
    let input_hash = sha256_json(&request.payload.payload);

    // Execute with the given payload.
    let output = match lang {
        Language::Js | Language::Ts => execute_with_node(&code, &request.payload.payload)
            .await
            .map_err(|e| EnclaveError::GenericError(format!("Node execution failed: {}", e)))?,
        Language::Py => execute_with_python(&code, &request.payload.payload)
            .await
            .map_err(|e| EnclaveError::GenericError(format!("Python execution failed: {}", e)))?,
    };

    // Build signed response. Timestamp is carried in IntentMessage.
    let now_ms = chrono::Utc::now().timestamp_millis() as u64;
    let payload = RuntimeResult {
        program_id: request.payload.blob_id.clone(),
        code_hash,
        input_hash,
        output,
    };

    Ok(Json(to_signed_response(
        &state.eph_kp,
        payload,
        now_ms,
        IntentScope::ProcessData,
    )))
}

// ---- Helpers ----

fn sha256_hex(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    hex::encode(hasher.finalize())
}

fn sha256_json(value: &Value) -> String {
    sha256_hex(&serde_json::to_string(value).unwrap_or_default())
}

fn detect_language(code: &str) -> Language {
    let trimmed = code.trim();
    if trimmed.contains("def main") {
        return Language::Py;
    }
    if trimmed.contains("export") || trimmed.contains("async function main") {
        return Language::Js;
    }
    if trimmed.contains("function main") {
        return Language::Js;
    }
    Language::Js
}

// ---- JS/Node execution ----

async fn execute_with_node(code: &str, payload: &Value) -> anyhow::Result<Value> {
    let normalized = normalize_js(code);
    let wrapper = format!(
        r#"
const input = JSON.parse(process.argv[2]);

async function __run() {{
{user_code}

  if (typeof main !== 'function') {{
    throw new Error('main(input) is not defined');
  }}

  const result = await main(input);
  process.stdout.write(JSON.stringify(result));
}}

__run().catch(e => {{
  console.error(e);
  process.exit(1);
}});
"#,
        user_code = normalized
    );

    let temp_path = write_temp_js(&wrapper)?;
    let child = Command::new("node")
        .arg(&temp_path)
        .arg(serde_json::to_string(payload)?)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let output = child.wait_with_output().await?;
    if !output.status.success() {
        anyhow::bail!("node error: {}", String::from_utf8_lossy(&output.stderr));
    }
    let v = serde_json::from_str::<Value>(String::from_utf8_lossy(&output.stdout).trim())?;
    Ok(v)
}

fn normalize_js(code: &str) -> String {
    code.replace("export async function main", "async function main")
        .replace("export function main", "function main")
        .replace("export const main", "const main")
}

fn write_temp_js(content: &str) -> anyhow::Result<std::path::PathBuf> {
    let mut p = std::env::temp_dir();
    p.push(format!("js_tmp_{}.mjs", Uuid::new_v4()));
    std::fs::write(&p, content)?;
    Ok(p)
}

// ---- Python execution ----

async fn execute_with_python(code: &str, payload: &Value) -> anyhow::Result<Value> {
    let escaped_user_code = code.replace("'''", r"\'\'\'");
    let wrapper = format!(
        r#"
import json, sys, contextlib, io

USER_CODE = '''{user_code}'''

globals_dict = {{}}
exec(USER_CODE, globals_dict)

if "main" not in globals_dict:
    raise RuntimeError("main(input) is not defined")

input_data = json.loads(sys.argv[1])

buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    result = globals_dict["main"](input_data)

if buf.getvalue():
    sys.stderr.write(buf.getvalue())

print(json.dumps(result))
"#,
        user_code = escaped_user_code
    );

    let child = Command::new("python")
        .arg("-u")
        .arg("-c")
        .arg(wrapper)
        .arg(serde_json::to_string(payload)?)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let output = child.wait_with_output().await?;
    if !output.status.success() {
        anyhow::bail!("python error: {}", String::from_utf8_lossy(&output.stderr));
    }
    let v = serde_json::from_str::<Value>(String::from_utf8_lossy(&output.stdout).trim())?;
    Ok(v)
}
