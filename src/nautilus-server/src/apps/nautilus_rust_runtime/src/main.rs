use axum::{Json, Router, extract::State, http::StatusCode, response::IntoResponse, routing::post};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    process::Stdio,
    sync::{Arc, RwLock},
};
use tokio::process::Command;
use uuid::Uuid;
use walrus_rs::WalrusClient;

// --------------------------------------------------------
// Types
// --------------------------------------------------------

type ProgramId = String;

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Language {
    Js,
    Ts,
    Py,
}

#[derive(Debug, Clone)]
struct ProgramRecord {
    id: ProgramId,
    language: Language,
    code: String,
    code_hash: String,
}

#[derive(Debug, Deserialize)]
struct RegisterProgramRequest {
    id: Option<String>,
    language: Language,
    code: String,
}

#[derive(Debug, Serialize)]
struct RegisterProgramResponse {
    id: String,
    language: Language,
    code_hash: String,
}

#[derive(Debug, Deserialize)]
struct ExecuteProgramRequest {
    id: String,
    payload: Value,
}

#[derive(Debug, Serialize)]
struct ExecutionResponse {
    program_id: String,
    code_hash: String,
    input_hash: String,
    output: Value,
    timestamp_ms: u64,
}

#[derive(Debug, Serialize)]
struct ExecuteProgramResponse {
    response: ExecutionResponse,
}

#[derive(Debug, Deserialize)]
struct ExecuteFromBlobRequest {
    blob_id: String,
    payload: Value,
}

// --------------------------------------------------------
// Helpers
// --------------------------------------------------------

fn sha256_hex(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    hex::encode(hasher.finalize())
}

fn sha256_json(value: &Value) -> String {
    sha256_hex(&serde_json::to_string(value).unwrap_or_default())
}

/// 自動偵測語言
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

    // default
    Language::Js
}

// --------------------------------------------------------
// AppState
// --------------------------------------------------------

struct AppState {
    programs: RwLock<HashMap<ProgramId, ProgramRecord>>,
    walrus_client: WalrusClient,
}

type SharedState = Arc<AppState>;

// --------------------------------------------------------
// Main
// --------------------------------------------------------

#[tokio::main]
async fn main() {
    let aggregator_url = std::env::var("AGGREGATOR")
        .unwrap_or_else(|_| "https://aggregator.testnet.walrus.atalma.io".to_string());
    let publisher_url = std::env::var("PUBLISHER")
        .unwrap_or_else(|_| "https://publisher.walrus-01.tududes.com".to_string());

    let walrus_client =
        WalrusClient::new(&aggregator_url, &publisher_url).expect("failed to create WalrusClient");

    let state: SharedState = Arc::new(AppState {
        programs: RwLock::new(HashMap::new()),
        walrus_client,
    });

    let app = Router::new()
        .route("/register_program", post(register_program))
        .route("/execute_program", post(execute_program))
        .route("/execute_program_from_blob", post(execute_program_from_blob))
        .with_state(state);

    let addr = "127.0.0.1:3001";
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind");

    println!("Rust runtime listening on http://{addr}");

    axum::serve(listener, app).await.expect("server error");
}

// --------------------------------------------------------
// Handlers
// --------------------------------------------------------

async fn register_program(
    State(state): State<SharedState>,
    Json(req): Json<RegisterProgramRequest>,
) -> impl IntoResponse {
    let id = req.id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let code_hash = sha256_hex(&req.code);

    let record = ProgramRecord {
        id: id.clone(),
        language: req.language,
        code: req.code.clone(),
        code_hash: code_hash.clone(),
    };

    state.programs.write().unwrap().insert(id.clone(), record);

    let resp = RegisterProgramResponse {
        id,
        language: req.language,
        code_hash,
    };

    (StatusCode::OK, Json(resp))
}

// --------------------------------------------------------
// Execute from Blob (with auto-detect)
// --------------------------------------------------------

async fn execute_program_from_blob(
    State(state): State<SharedState>,
    Json(req): Json<ExecuteFromBlobRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    // 1. read blob
    let code_bytes = state
        .walrus_client
        .read_blob_by_id(&req.blob_id)
        .await
        .map_err(|e| {
            (
                StatusCode::BAD_GATEWAY,
                Json(json!({
                    "error": "walrus_read_failed",
                    "message": e.to_string(),
                })),
            )
        })?;

    // 2. convert to text
    let blob_text = String::from_utf8(code_bytes).map_err(|e| {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({
                "error": "invalid_utf8_from_blob",
                "message": e.to_string(),
            })),
        )
    })?;

    // 3. If JSON → extract code
    let code = if blob_text.trim_start().starts_with('{') {
        let v: Value = serde_json::from_str(&blob_text).map_err(|e| {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": "invalid_blob_json",
                    "message": e.to_string(),
                })),
            )
        })?;

        v.get("code")
            .and_then(|c| c.as_str())
            .map(|s| s.to_string())
            .ok_or_else(|| {
                (
                    StatusCode::BAD_REQUEST,
                    Json(json!({
                        "error": "json_missing_code_field"
                    })),
                )
            })?
    } else {
        blob_text
    };

    // 4. detect language
    let lang = detect_language(&code);

    // 5. compute hashes
    let code_hash = sha256_hex(&code);
    let input_hash = sha256_json(&req.payload);
    let timestamp_ms = chrono::Utc::now().timestamp_millis() as u64;

    // 6. execute
    let output = match lang {
        Language::Js | Language::Ts => execute_with_node(&code, &req.payload).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "error":"execution_failed",
                    "engine":"node",
                    "message":e.to_string(),
                })),
            )
        })?,
        Language::Py => execute_with_python(&code, &req.payload).await.map_err(|e| {
            (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({
                    "error":"execution_failed",
                    "engine":"python",
                    "message":e.to_string(),
                })),
            )
        })?,
    };

    // 7. final unified response format
    let resp = ExecuteProgramResponse {
        response: ExecutionResponse {
            program_id: req.blob_id,
            code_hash,
            input_hash,
            output,
            timestamp_ms,
        },
    };

    Ok((StatusCode::OK, Json(resp)))
}


// --------------------------------------------------------
// JavaScript / Node execution
// --------------------------------------------------------

async fn execute_with_node(
    code: &str,
    payload: &serde_json::Value,
) -> anyhow::Result<serde_json::Value> {
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

// --------------------------------------------------------
// Python execution
// --------------------------------------------------------

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

/// 寫 temp JS
fn write_temp_js(content: &str) -> anyhow::Result<std::path::PathBuf> {
    let mut p = std::env::temp_dir();
    p.push(format!("js_tmp_{}.mjs", Uuid::new_v4()));
    std::fs::write(&p, content)?;
    Ok(p)
}

async fn execute_program(
    State(state): State<SharedState>,
    Json(req): Json<ExecuteProgramRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    // 1. Load program from memory
    let program = {
        let programs = state.programs.read().unwrap();
        match programs.get(&req.id) {
            Some(record) => record.clone(),
            None => {
                return Err((
                    StatusCode::NOT_FOUND,
                    Json(json!({ "error": "program not found" })),
                ));
            }
        }
    };

    let input_hash = sha256_json(&req.payload);
    let timestamp_ms = chrono::Utc::now().timestamp_millis() as u64;

    // 2. Execute according to language
    let output = match program.language {
        Language::Js | Language::Ts => execute_with_node(&program.code, &req.payload)
            .await
            .map_err(|err| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({
                        "error": "execution_failed",
                        "engine": "node",
                        "message": err.to_string(),
                    })),
                )
            })?,
        Language::Py => execute_with_python(&program.code, &req.payload)
            .await
            .map_err(|err| {
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(json!({
                        "error": "execution_failed",
                        "engine": "python",
                        "message": err.to_string(),
                    })),
                )
            })?,
    };

    // 3. Build response
    let resp = ExecuteProgramResponse {
        response: ExecutionResponse {
            program_id: program.id,
            code_hash: program.code_hash,
            input_hash,
            output,
            timestamp_ms,
        },
    };

    Ok((StatusCode::OK, Json(resp)))
}
