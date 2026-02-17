from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    DATABASE_URL: str = "postgresql+asyncpg://umbra:umbra_dev@localhost:5432/umbra"
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
    APNS_BUNDLE_ID: str = "com.umbra.ios"
    APNS_USE_SANDBOX: bool = True

    ENVIRONMENT: str = "development"
    RATE_LIMIT_PER_MINUTE: int = 100

    model_config = {"env_file": ".env", "extra": "ignore"}


settings = Settings()
