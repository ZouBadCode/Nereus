use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    process::Stdio,
    sync::{Arc, RwLock},
    io::Write,
};
use std::fs;
use tokio::process::Command;
use uuid::Uuid;

type ProgramId = String;

/// 共享的 AppState 走 Arc 包起來（跟官方範例同一種寫法）
/// Router 的 state 型別 = `SharedState`
#[derive(Debug)]
struct AppState {
    programs: RwLock<HashMap<ProgramId, ProgramRecord>>,
}

type SharedState = Arc<AppState>;

#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
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
    // 之後要加簽名可以在這裡加 field
}

fn sha256_hex(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    let out = hasher.finalize();
    hex::encode(out)
}

fn sha256_json(value: &Value) -> String {
    let s = serde_json::to_string(value).unwrap_or_default();
    sha256_hex(&s)
}

fn write_temp_js(content: &str) -> anyhow::Result<std::path::PathBuf> {
    use std::env;
    use std::path::PathBuf;

    // 取得系統暫存資料夾，例如 /tmp 或 C:\Users\...\AppData\Local\Temp
    let mut path: PathBuf = env::temp_dir();
    path.push(format!("nautilus_js_{}.mjs", Uuid::new_v4()));

    // 用 std::fs 建立檔案並寫入內容
    let mut file = fs::File::create(&path)?;
    file.write_all(content.as_bytes())?;

    Ok(path)
}

#[tokio::main]
async fn main() {
    // 初始化共享 state
    let state: SharedState = Arc::new(AppState {
        programs: RwLock::new(HashMap::new()),
    });

    let app = Router::new()
        .route("/register_program", post(register_program))
        .route("/execute_program", post(execute_program))
        // 這裡 with_state 的型別 = SharedState = Arc<AppState>
        .with_state(state);

    let addr = "127.0.0.1:3000";
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("failed to bind");

    println!("Rust runtime listening on http://{addr}");

    axum::serve(listener, app)
        .await
        .expect("server error");
}

// -------- Handlers --------

async fn register_program(
    State(state): State<SharedState>,
    Json(req): Json<RegisterProgramRequest>,
) -> impl IntoResponse {
    let id = req.id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let normalized_code = req.code.clone();
    let code_hash = sha256_hex(&normalized_code);

    let record = ProgramRecord {
        id: id.clone(),
        language: req.language,
        code: normalized_code,
        code_hash: code_hash.clone(),
    };

    {
        let mut programs = state.programs.write().unwrap();
        programs.insert(id.clone(), record);
    }

    let resp = RegisterProgramResponse {
        id,
        language: req.language,
        code_hash,
    };

    (StatusCode::OK, Json(resp))
}

async fn execute_program(
    State(state): State<SharedState>,
    Json(req): Json<ExecuteProgramRequest>,
) -> Result<impl IntoResponse, (StatusCode, Json<Value>)> {
    // ---- 1. 取程式紀錄 ----
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

    // ---- 2. 根據語言執行 ----
    let output = match program.language {
        Language::Js | Language::Ts => {
            execute_with_node(&program.code, &req.payload)
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
                })?
        }
        Language::Py => {
            execute_with_python(&program.code, &req.payload)
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
                })?
        }
    };

    // ---- 3. 回傳標準化結果 ----
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

// -------- JS / TS (用 node 子行程) --------
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
        user_code = normalized,
    );

    // ✅ 寫入 temp 檔案，不用 node -e
    let temp_path = write_temp_js(&wrapper)?;

    let child = Command::new("node")
        .arg(&temp_path) // PathBuf 可以直接當成 arg
        .arg(serde_json::to_string(payload)?)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let output = child.wait_with_output().await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("node error: {}", stderr);
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: serde_json::Value = serde_json::from_str(stdout.trim())?;
    Ok(v)
}

fn normalize_js(code: &str) -> String {
    code.replace("export async function main", "async function main")
        .replace("export function main", "function main")
        .replace("export const main", "const main")
}

// -------- Python --------

async fn execute_with_python(code: &str, payload: &Value) -> anyhow::Result<Value> {
    // 先處理掉使用者程式裡的三單引號，避免打壞 Python 的 ''' 字串
    let escaped_user_code = code.replace("'''", r"\'\'\'");

    let wrapper = format!(
        r#"
import json, sys, contextlib, io

USER_CODE = '''{user_code}'''

globals_dict = {{}}
exec(USER_CODE, globals_dict)

if "main" not in globals_dict or not callable(globals_dict["main"]):
    raise RuntimeError("main(input) is not defined")

input_data = json.loads(sys.argv[1])

buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    result = globals_dict["main"](input_data)

# 把使用者程式印出來的東西丟到 stderr，方便 debug
debug_output = buf.getvalue()
if debug_output:
    sys.stderr.write(debug_output)

print(json.dumps(result))
"#,
        user_code = escaped_user_code
    );

    let child = Command::new("python")
        .arg("-u")
        .arg("-c")
        .arg(wrapper)
        .arg(serde_json::to_string(payload)?)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let output = child.wait_with_output().await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("python error: {stderr}");
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let v: Value = serde_json::from_str(stdout.trim())?;
    Ok(v)
}