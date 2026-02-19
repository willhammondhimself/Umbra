from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+asyncpg://tether:tether_dev@localhost:5432/tether"
    REDIS_URL: str = "redis://localhost:6379/0"

    JWT_SECRET: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    APPLE_TEAM_ID: str = ""
    GOOGLE_CLIENT_ID: str = ""

    # APNs Configuration
    APNS_KEY_ID: str = ""
    APNS_TEAM_ID: str = ""
    APNS_KEY_PATH: str = ""  # Path to .p8 key file
    APNS_BUNDLE_ID: str = "com.willhammond.tether.ios"
    APNS_USE_SANDBOX: bool = True

    # AI Coaching
    OPENAI_API_KEY: str = ""
    ANTHROPIC_API_KEY: str = ""
    AI_PROVIDER: str = ""  # "openai" or "anthropic"
    AI_MODEL: str = ""  # Override default model per provider

    # Third-Party Integrations
    SLACK_CLIENT_ID: str = ""
    SLACK_CLIENT_SECRET: str = ""
    TODOIST_CLIENT_ID: str = ""
    NOTION_API_KEY: str = ""

    # Observability
    SENTRY_DSN: str = ""

    # Email (SMTP)
    SMTP_HOST: str = ""
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_FROM_EMAIL: str = "noreply@tether.app"
    FRONTEND_URL: str = "https://tether.app"

    # StoreKit / App Store
    APP_STORE_SHARED_SECRET: str = ""

    ENVIRONMENT: str = "development"
    RATE_LIMIT_PER_MINUTE: int = 100

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
