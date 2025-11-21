# Host Proxy

A lightweight Axum-based HTTPS forward proxy for AWS Nitro Enclaves.

## Purpose
The enclave has no direct network access; it sends structured JSON requests over a vsock-forwarded TCP channel to this proxy. The proxy validates an upstream whitelist then performs outbound HTTPS requests and returns sanitized responses.

## Endpoint
`POST /proxy`
```json
{
  "method": "GET",
  "upstream": "api.openweathermap.org",
  "path": "/data/2.5/weather?q=Taipei&appid=YOUR_KEY",
  "headers": {"Accept": "application/json"},
  "body": "optional string"
}
```

Response:
```json
{
  "status": 200,
  "body": "<raw upstream body>",
  "headers": {"content-type": "application/json"}
}
```
On error:
```json
{"error": "upstream_not_allowed", "message": "Upstream domain is not whitelisted"}
```

## Running
Build and run inside parent instance:
```bash
cargo build -p host-proxy --release
RUST_LOG=info ./target/release/host-proxy
```
Forward traffic to enclave (example, adjust CIDs/ports):
```bash
python3 traffic_forwarder.py 127.0.0.1 8081 <ENCLAVE_CID> 8081
```

## Security Hardening Ideas
- Add request signature (enclave PK + signature). 
- Rate limiting per upstream.
- Response size caps.
- Attestation check on first request.
- Structured audit logs.

## Modify Whitelist
Edit `allowed` vector in `main.rs` or externalize via env:
`ALLOWED_UPSTREAMS=api.openweathermap.org,api.example.com` (future enhancement).

