---
globs: ["backend/routes/**", "backend/api/**", "supabase/functions/**"]
---

> **Tone:** These rules are instructions for Claude to follow automatically and narrate in plain English. During build mode, apply them silently. During deploy mode, they become enforcement criteria.

## Response Envelope

Always wrap API responses in a consistent envelope. Narrate: "I set up a standard response format so the frontend always knows what to expect."

```python
# Success
{"status": "ok", "data": <payload>, "meta": {"request_id": "<correlation_id>"}}

# Error
{"status": "error", "error": {"code": "<ERROR_CODE>", "message": "<user-safe message>"}, "meta": {"request_id": "<correlation_id>"}}

# Paginated
{"status": "ok", "data": [<items>], "meta": {"request_id": "<id>", "pagination": {"cursor": "<next>", "has_more": true, "total": 142}}}
```

## Input Validation

- Always validate request bodies with Pydantic models. Narrate: "I added input validation to catch bad data before it reaches the database."
- Always add type annotations with constraints (gt=0, max_length, regex) to path and query parameters. Narrate: "I added parameter constraints so invalid values get caught early."
- Always validate MIME type and size for file uploads before processing. Narrate: "I added file validation to make sure only safe file types are accepted."
- Always derive user identity from the JWT — never trust client-supplied IDs for authorization. Narrate: "I pull the user identity from their login token so nobody can pretend to be someone else."

## Pagination

- Always use cursor-based pagination for list endpoints. Narrate: "I set up pagination so the app stays fast even with lots of data."
- Default page size: 20, maximum: 100.
- Always return `has_more` and `cursor` in the pagination meta.
- Sort by `created_at` descending unless the endpoint specifies otherwise.

## HTTP Status Codes

Always use the correct status codes automatically:

- 200: Successful read or update
- 201: Successful creation (include Location header)
- 204: Successful deletion (no body)
- 400: Validation error (include field-level details in error.details)
- 401: Not authenticated (missing or invalid token)
- 403: Authenticated but not authorized for this resource
- 404: Resource not found (always return 404 for both "doesn't exist" and "no access" to prevent enumeration)
- 409: Conflict (duplicate resource, version mismatch)
- 422: Unprocessable entity (valid syntax but semantic error)
- 429: Rate limited (include Retry-After header)
- 500: Internal server error (log the stack trace server-side, return only a generic message to the client)

## Error Handling

- Always wrap route handlers with error catching using FastAPI exception handlers. Narrate: "I added error handling so unexpected problems get logged without exposing details to users."
- Always generate a correlation ID (uuid4) at middleware level and attach it to every log entry and response.
- Always log the full exception with stack trace server-side using structured logging.
- Always return only the correlation ID and a generic message to the client — never expose database errors, file paths, internal service names, or query details.

## Rate Limiting

- Always apply rate limiting at the middleware level. Narrate: "I added rate limiting so nobody can overload your app."
- Always include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` headers.
- Always apply stricter limits to auth endpoints (login, register, reset password).
