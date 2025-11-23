use std::convert::Infallible;
use std::net::SocketAddr;

use hyper::http::uri::Authority;
use hyper::client::HttpConnector;
use hyper::header::HOST;
use hyper::server::conn::AddrStream;
use hyper::service::{make_service_fn, service_fn};
use hyper::{upgrade, Body, Client, Method, Request, Response, Server, StatusCode};
use log::{error, info};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    env_logger::init();

    // Listen address for the proxy (Host EC2).
    // Example: 0.0.0.0:8080 or 127.0.0.1:8080
    let listen_addr: SocketAddr = std::env::var("PROXY_LISTEN_ADDR")
        .unwrap_or_else(|_| "0.0.0.0:8080".to_string())
        .parse()
        .expect("Invalid PROXY_LISTEN_ADDR");

    // Underlying HTTP client used to talk to upstream servers.
    let mut connector = HttpConnector::new();
    connector.enforce_http(false); // allow http + https
    let client: Client<HttpConnector> = Client::builder().build(connector);

    info!("Starting proxy on {}", listen_addr);

    let make_svc = make_service_fn(move |_conn: &AddrStream| {
        let client = client.clone();
        async move {
            Ok::<_, Infallible>(service_fn(move |req| {
                proxy_service(req, client.to_owned())
            }))
        }
    });

    let server = Server::bind(&listen_addr).serve(make_svc);

    if let Err(e) = server.await {
        error!("server error: {}", e);
    }

    Ok(())
}

async fn proxy_service(
    req: Request<Body>,
    client: Client<HttpConnector>,
) -> Result<Response<Body>, Infallible> {
    // Handle HTTPS via CONNECT
    if req.method() == Method::CONNECT {
        match handle_connect(req).await {
            Ok(resp) => Ok(resp),
            Err(e) => {
                error!("CONNECT error: {:?}", e);
                Ok(Response::builder()
                    .status(StatusCode::BAD_GATEWAY)
                    .body(Body::from(format!("CONNECT error: {e}")))
                    .unwrap())
            }
        }
    } else {
        // Normal HTTP (GET/POST/...)
        match handle_http(req, client).await {
            Ok(resp) => Ok(resp),
            Err(e) => {
                error!("HTTP proxy error: {:?}", e);
                Ok(Response::builder()
                    .status(StatusCode::BAD_GATEWAY)
                    .body(Body::from(format!("HTTP proxy error: {e}")))
                    .unwrap())
            }
        }
    }
}

/// Handle normal HTTP requests (non-CONNECT).
async fn handle_http(
    mut req: Request<Body>,
    client: Client<HttpConnector>,
) -> Result<Response<Body>, anyhow::Error> {
    // Extract original URI and authority (host:port).
    let orig_uri = req.uri().clone();

    let authority: Authority = match orig_uri.authority().cloned() {
        Some(a) => a,
        None => {
            // Some libs might not send absolute-form. Try Host header.
            let host = req
                .headers()
                .get(HOST)
                .and_then(|h| h.to_str().ok())
                .ok_or_else(|| anyhow::anyhow!("missing authority and Host header"))?;
            host.parse::<Authority>()?
        }
    };

    let scheme = orig_uri
        .scheme_str()
        .unwrap_or("http"); // default http if missing

    let path_and_query = orig_uri
        .path_and_query()
        .map(|pq| pq.as_str())
        .unwrap_or("/");

    // Build new URI for the outgoing request, e.g. "http://example.com/path?x=1"
    let new_uri = format!("{}://{}{}", scheme, authority, path_and_query);
    *req.uri_mut() = new_uri
        .parse()
        .map_err(|e| anyhow::anyhow!("failed to parse new uri: {e}"))?;

    // Ensure Host header is set to upstream authority
    req.headers_mut()
        .insert(HOST, authority.as_str().parse().unwrap());

    info!(
        "HTTP {} {}",
        req.method(),
        req.uri()
    );

    let resp = client.request(req).await?;
    Ok(resp)
}

/// Handle HTTPS CONNECT tunneling.
/// Example CONNECT line: "CONNECT api.example.com:443 HTTP/1.1"
async fn handle_connect(req: Request<Body>) -> Result<Response<Body>, anyhow::Error> {
    let host = req
        .uri()
        .authority()
        .ok_or_else(|| anyhow::anyhow!("CONNECT missing authority"))?
        .clone();

    info!("CONNECT {}", host);

    // Establish connection to the target host:port
    let target_stream = tokio::net::TcpStream::connect(host.as_str()).await?;

    // Send 200 Connection Established back to client.
    let mut resp = Response::new(Body::empty());
    *resp.status_mut() = StatusCode::OK;

    // Spawn a task to handle the upgraded connection.
    tokio::spawn(async move {
        match upgrade::on(req).await {
            Ok(mut upgraded) => {
                let mut target = target_stream;
                let _ = tokio::io::copy_bidirectional(&mut upgraded, &mut target).await;
            }
            Err(e) => {
                error!("upgrade error in CONNECT: {}", e);
            }
        }
    });

    Ok(resp)
}
