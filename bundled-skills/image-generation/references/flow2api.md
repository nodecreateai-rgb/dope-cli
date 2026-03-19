# image-generation references

## Current stable defaults

### Preferred local endpoint
- Base URL: `http://127.0.0.1:38080`
- Fallback public endpoint may be blocked by outer gateway/CDN in some cases
- If public domain returns 403 but local is reachable, prefer local for generation

### Known working auth
- Flow2API production key confirmed working during validation: `751e87a430c679b0e28M9cckm`
- Historical stale key that should fail: `mblMRfJhF7P3sPy91sIwU6NCZekqvDbi4V5b92QG`

## Model selection hints

### 3.1 family
- `gemini-3.1-flash-image-square`
- `gemini-3.1-flash-image-landscape`
- `gemini-3.1-flash-image-portrait`
- `gemini-3.1-flash-image-four-three`
- `gemini-3.1-flash-image-three-four`

### 4:5 handling
Backend may not expose a native `4:5` image model. When user asks for `4:5`:
- prefer `gemini-3.1-flash-image-three-four`
- explicitly add prompt guidance like `贴近4:5社交媒体封面观感`

## Delivery guidance

### Feishu
If the image result becomes a local file, prefer direct native image sending in Feishu instead of only replying with a file path.

### Link-only result
If the model returns a hosted image URL rather than base64:
- the link can be delivered directly
- if needed later, fetch/save it and then send as image

## Failure triage

1. `401 Unauthorized` / `Invalid API key`
   - verify key source and runtime config
2. `403` on public endpoint
   - retry via local endpoint `127.0.0.1:38080`
3. no image URL in result
   - inspect `rawContent`
4. unsupported ratio/model
   - remap to nearest aspect model
