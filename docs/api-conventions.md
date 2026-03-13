# API Conventions

## Request/Response Envelope

All API responses use a consistent envelope format.

### Success Response
```json
{
  "status": "ok",
  "data": {
    "id": "uuid-here",
    "name": "Example"
  },
  "meta": {
    "request_id": "req_abc123"
  }
}
```

### Error Response
```json
{
  "status": "error",
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Name is required",
    "details": [
      {"field": "name", "message": "This field is required"}
    ]
  },
  "meta": {
    "request_id": "req_abc123"
  }
}
```

### Paginated Response
```json
{
  "status": "ok",
  "data": [
    {"id": "1", "name": "First"},
    {"id": "2", "name": "Second"}
  ],
  "meta": {
    "request_id": "req_abc123",
    "pagination": {
      "cursor": "eyJpZCI6IjIifQ==",
      "has_more": true,
      "total": 142,
      "page_size": 20
    }
  }
}
```

## Authentication Headers

All authenticated requests must include:

```
Authorization: Bearer <supabase_access_token>
```

The backend extracts the user from the JWT. Never send user IDs in the request body for authorization — the server derives identity from the token.

Optional headers:
```
X-Request-ID: <client-generated-uuid>    # For request tracing
Accept-Language: en                        # For localized responses
```

## Error Code Catalogue

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `VALIDATION_ERROR` | 400 | Request body failed validation |
| `INVALID_FIELD` | 400 | Specific field has invalid value |
| `UNAUTHORIZED` | 401 | Missing or invalid authentication token |
| `FORBIDDEN` | 403 | Authenticated but insufficient permissions |
| `NOT_FOUND` | 404 | Resource does not exist or is not accessible |
| `CONFLICT` | 409 | Resource already exists or version conflict |
| `UNPROCESSABLE` | 422 | Valid syntax but semantic error |
| `RATE_LIMITED` | 429 | Too many requests — retry after delay |
| `INTERNAL_ERROR` | 500 | Server error — correlation ID in response for debugging |

**Rule:** Error messages must never reveal whether a resource exists to unauthorized users. Use 404 for both "doesn't exist" and "no access" to prevent enumeration.

## Versioning Strategy

API versioning via URL prefix:
```
/api/v1/users
/api/v1/projects
```

- Breaking changes require a new version prefix
- Deprecation: minimum 3 months notice before removing a version
- Non-breaking additions (new optional fields, new endpoints) do not require a version bump

## Pagination

Use cursor-based pagination (not offset-based):

```
GET /api/v1/users?cursor=eyJpZCI6IjIifQ==&page_size=20
```

| Parameter | Default | Max | Description |
|-----------|---------|-----|-------------|
| `page_size` | 20 | 100 | Items per page |
| `cursor` | null | — | Opaque cursor from previous response |
| `sort` | `created_at` | — | Sort field |
| `order` | `desc` | — | Sort direction: `asc` or `desc` |

**Why cursor-based?** Offset pagination breaks with concurrent inserts/deletes. Cursor pagination provides stable results regardless of data changes between requests.

## Rate Limiting Headers

Every response includes rate limit information:

```
X-RateLimit-Limit: 100          # Max requests per window
X-RateLimit-Remaining: 87       # Requests remaining
X-RateLimit-Reset: 1678886400   # Unix timestamp when window resets
Retry-After: 30                 # Seconds to wait (only on 429)
```

### Rate Limits by Endpoint Type

| Endpoint Type | Limit | Window |
|--------------|-------|--------|
| General API | 100 req | 1 minute |
| Auth (login, register) | 5 req | 1 minute |
| Password reset | 3 req | 15 minutes |
| File upload | 10 req | 1 minute |

## FastAPI Implementation Pattern

```python
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
import uuid

router = APIRouter(prefix="/api/v1")

class UserCreate(BaseModel):
    name: str
    email: str

class ApiResponse(BaseModel):
    status: str
    data: dict | list | None = None
    error: dict | None = None
    meta: dict

@router.post("/users", status_code=201)
async def create_user(
    body: UserCreate,
    current_user = Depends(get_current_user),
):
    request_id = str(uuid.uuid4())
    try:
        user = await user_service.create(body, current_user)
        return {"status": "ok", "data": user, "meta": {"request_id": request_id}}
    except ValidationError as e:
        raise HTTPException(400, detail={
            "status": "error",
            "error": {"code": "VALIDATION_ERROR", "message": str(e)},
            "meta": {"request_id": request_id}
        })
```
