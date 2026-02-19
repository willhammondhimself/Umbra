from contextlib import asynccontextmanager

import redis.asyncio as redis
import sentry_sdk
from fastapi import FastAPI

from app.config import settings
from app.database import engine

# Initialize Sentry
if settings.SENTRY_DSN:
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        environment=settings.ENVIRONMENT,
        traces_sample_rate=0.2 if settings.ENVIRONMENT == "production" else 1.0,
        profiles_sample_rate=0.1,
        send_default_pii=False,
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: verify DB connection and connect Redis
    async with engine.begin() as conn:
        await conn.execute(
            __import__("sqlalchemy").text("SELECT 1")
        )

    app.state.redis = redis.from_url(
        settings.REDIS_URL,
        decode_responses=True,
    )
    await app.state.redis.ping()

    # APNs client for push notifications
    app.state.apns_client = None
    if settings.APNS_KEY_PATH:
        try:
            from aioapns import APNs

            app.state.apns_client = APNs(
                key=settings.APNS_KEY_PATH,
                key_id=settings.APNS_KEY_ID,
                team_id=settings.APNS_TEAM_ID,
                topic=settings.APNS_BUNDLE_ID,
                use_sandbox=settings.APNS_USE_SANDBOX,
            )
        except (ImportError, Exception):
            # aioapns not available or config invalid — push notifications disabled
            app.state.apns_client = None

    yield

    # Shutdown
    await app.state.redis.close()
    await engine.dispose()


app = FastAPI(
    title="Tether API",
    version="0.1.0",
    lifespan=lifespan,
)

# Middleware
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402

_cors_origins = [
    "chrome-extension://*",
    "http://localhost:*",
    "https://api.tether.app",
    "https://tether.app",
    "https://www.tether.app",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from app.middleware.error_handler import register_error_handlers  # noqa: E402

register_error_handlers(app)

# Routers
from app.routers.auth import router as auth_router  # noqa: E402
from app.routers.projects import router as projects_router  # noqa: E402
from app.routers.sessions import router as sessions_router  # noqa: E402
from app.routers.stats import router as stats_router  # noqa: E402
from app.routers.social import router as social_router  # noqa: E402
from app.routers.tasks import router as tasks_router  # noqa: E402
from app.routers.devices import router as devices_router  # noqa: E402
from app.routers.insights import router as insights_router  # noqa: E402
from app.routers.blocklist import router as blocklist_router  # noqa: E402
from app.routers.webhooks import router as webhooks_router  # noqa: E402
from app.routers.integrations import router as integrations_router  # noqa: E402
from app.routers.parsing import router as parsing_router  # noqa: E402
from app.routers.subscriptions import router as subscriptions_router  # noqa: E402

app.include_router(auth_router)
app.include_router(projects_router)
app.include_router(tasks_router)
app.include_router(sessions_router)
app.include_router(stats_router)
app.include_router(social_router)
app.include_router(devices_router)
app.include_router(insights_router)
app.include_router(blocklist_router)
app.include_router(webhooks_router)
app.include_router(integrations_router)
app.include_router(parsing_router)
app.include_router(subscriptions_router)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/.well-known/apple-app-site-association")
async def apple_app_site_association():
    """Serve AASA for Universal Links."""
    return {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": "CT65B2T766.com.willhammond.tether.app",
                    "paths": ["/invite/*"],
                },
                {
                    "appID": "CT65B2T766.com.willhammond.tether.ios",
                    "paths": ["/invite/*"],
                },
            ],
        },
    }


@app.get("/invite/{code}")
async def invite_redirect(code: str):
    """Redirect invite links — Universal Links will intercept on iOS/macOS, web falls back."""
    from fastapi.responses import RedirectResponse

    return RedirectResponse(url=f"https://tether.app/join?code={code}")
