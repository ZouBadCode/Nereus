use axum::{routing::post, Router, extract::State, Json};
use serde::{Deserialize, Serialize};
use std::{net::SocketAddr, sync::Arc};
use reqwest::{Client, Method};
use tracing::{info, warn, error};
use tracing_subscriber::{fmt, EnvFilter};
use tracing_subscriber::prelude::*; // brings in .with()
use tokio::net::TcpListener;
use std::collections::HashMap;

#[derive(Deserialize)]
struct ProxyRequest {
    method: String,
    upstream: String,   // e.g. "api.openweathermap.org"
    path: String,       // e.g. "/data/2.5/weather?q=Taipei&appid=KEY"
    headers: Option<HashMap<String,String>>,
    body: Option<String>,
}

#[derive(Serialize)]
struct ProxyResponse {
    status: u16,
    body: String,
    headers: HashMap<String,String>,
}

struct AppState {
    client: Client,
    allowed: Vec<String>,
    max_body_bytes: usize,
}

async fn handle_proxy(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ProxyRequest>,
) -> Result<Json<ProxyResponse>, Json<HashMap<&'static str, String>>> {
    // Basic validation
    if !state.allowed.iter().any(|d| d == &req.upstream) {
        warn!(upstream = %req.upstream, "upstream not allowed");
        return Err(Json(err("upstream_not_allowed", "Upstream domain is not whitelisted")));
    }
    if !req.path.starts_with('/') {
        return Err(Json(err("bad_path", "Path must start with '/'")));
    }
    if req.method.len() > 10 { // quick sanity
        return Err(Json(err("bad_method", "Method too long")));
    }
    let method = match req.method.parse::<Method>() {
        Ok(m) => m,
        Err(_) => return Err(Json(err("bad_method", "Invalid HTTP method"))),
    };

    // Enforce HTTPS only for upstream call.
    let url = format!("https://{}{}", req.upstream, req.path);
    info!(%url, "proxying request");

    let mut builder = state.client.request(method, &url);
    if let Some(hs) = &req.headers {
        for (k,v) in hs {
            // Skip Host header injection.
            if k.eq_ignore_ascii_case("host") { continue; }
            builder = builder.header(k, v);
        }
    }

    let resp = if let Some(b) = &req.body {
        if b.len() > state.max_body_bytes {
            return Err(Json(err("body_too_large", "Request body exceeds limit")));
        }
        builder.body(b.clone()).send().await
    } else {
        builder.send().await
    };

    let resp = match resp {
        Ok(r) => r,
        Err(e) => {
            error!(error = %e, "Upstream request failed");
            return Err(Json(err("upstream_error", format!("{}", e).as_str())));
        }
    };

    let status = resp.status().as_u16();
    let mut out_headers = HashMap::new();
    for (k,v) in resp.headers().iter() {
        out_headers.insert(k.to_string(), v.to_str().unwrap_or("").to_string());
    }
    let body = match resp.text().await {
        Ok(b) => b,
        Err(e) => {
            error!(error = %e, "Reading body failed");
            return Err(Json(err("read_body_failed", format!("{}", e).as_str())));
        }
    };

    Ok(Json(ProxyResponse { status, body, headers: out_headers }))
}

fn err(code: &'static str, msg: &str) -> HashMap<&'static str, String> {
    let mut m = HashMap::new();
    m.insert("error", code.to_string());
    m.insert("message", msg.to_string());
    m
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Logging
    tracing_subscriber::registry()
        .with(fmt::layer())
        .with(EnvFilter::from_default_env())
        .init();

    let state = Arc::new(AppState {
        client: Client::builder()
            .timeout(std::time::Duration::from_secs(8))
            .build()?,
        allowed: vec![
            "api.openweathermap.org".into(),
            "api.example.com".into(),
        ],
        max_body_bytes: 64 * 1024, // 64KB
    });

    let app = Router::new().route("/proxy", post(handle_proxy)).with_state(state);
    let addr: SocketAddr = "0.0.0.0:8081".parse()?;
    let listener = TcpListener::bind(addr).await?;
    info!(%addr, "Host proxy listening");
    axum::serve(listener, app).await?;
    Ok(())
}
