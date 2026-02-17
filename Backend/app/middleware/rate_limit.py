import time

from fastapi import HTTPException, Request, status
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import settings


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Redis-backed sliding window rate limiter."""

    async def dispatch(self, request: Request, call_next):
        # Skip rate limiting for health check
        if request.url.path == "/health":
            return await call_next(request)

        # Get client identifier (IP or user from auth)
        client_ip = request.client.host if request.client else "unknown"
        key = f"rate_limit:{client_ip}"

        redis_client = getattr(request.app.state, "redis", None)
        if redis_client is None:
            # No Redis available, skip rate limiting
            return await call_next(request)

        try:
            now = time.time()
            window = 60  # 1-minute window

            pipe = redis_client.pipeline()
            # Remove old entries
            pipe.zremrangebyscore(key, 0, now - window)
            # Add current request
            pipe.zadd(key, {str(now): now})
            # Count requests in window
            pipe.zcard(key)
            # Set TTL on the key
            pipe.expire(key, window)
            results = await pipe.execute()

            request_count = results[2]

            if request_count > settings.RATE_LIMIT_PER_MINUTE:
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Rate limit exceeded. Try again later.",
                )
        except HTTPException:
            raise
        except Exception:
            # If Redis fails, allow the request through
            pass

        return await call_next(request)
