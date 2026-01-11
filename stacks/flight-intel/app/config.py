"""Configuration management using Pydantic settings."""

from typing import List

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Database
    database_url: str = Field(
        default="postgresql://flightintel:flightintel@localhost:5432/flightintel"
    )
    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_user: str = "flightintel"
    postgres_password: str = "flightintel"
    postgres_db: str = "flightintel"

    # Redis
    redis_url: str = "redis://localhost:6379/0"
    redis_enabled: bool = False

    # API
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_key: str = "dev_api_key"
    api_cors_origins: str = "http://localhost:8501,http://localhost:8000"

    # Collector
    collector_schedule: str = "0 3 * * *"
    collector_enabled: bool = True
    collector_timeout_seconds: int = 3600
    collector_batch_size: int = 10

    # Providers
    default_provider: str = "mock"
    amadeus_api_key: str = ""
    amadeus_api_secret: str = ""
    amadeus_base_url: str = "https://test.api.amadeus.com"

    # Search configuration
    default_origins: str = "AMS,EIN,RTM,BRU"
    default_destinations: str = "HER,CHQ"
    search_start_days_ahead: int = 7
    search_end_days_ahead: int = 180
    min_stay_days: int = 7
    max_stay_days: int = 21
    default_cabin: str = "ECONOMY"
    max_stops: int = 2
    currency: str = "EUR"

    # Recommendation engine
    reco_history_window_days: int = 60
    reco_buy_margin: float = 0.05
    reco_median_discount: float = 0.10
    reco_trend_threshold: float = -0.5

    # LLM Agent
    agent_enabled: bool = False
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "llama2"

    # Observability
    log_level: str = "INFO"
    log_format: str = "json"
    log_file: str = "/var/log/flight-intel/app.log"
    metrics_enabled: bool = True
    metrics_port: int = 9090

    # Alerts
    alerts_enabled: bool = False
    ntfy_url: str = "http://localhost:80"
    ntfy_topic: str = "flight-intel-alerts"
    telegram_enabled: bool = False
    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    email_enabled: bool = False
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    email_from: str = ""
    email_to: str = ""

    # Security
    environment: str = "development"
    jwt_secret: str = "dev_secret_change_me_in_production"

    @property
    def origins_list(self) -> List[str]:
        """Parse origins from comma-separated string."""
        return [o.strip() for o in self.default_origins.split(",") if o.strip()]

    @property
    def destinations_list(self) -> List[str]:
        """Parse destinations from comma-separated string."""
        return [d.strip() for d in self.default_destinations.split(",") if d.strip()]

    @property
    def cors_origins_list(self) -> List[str]:
        """Parse CORS origins from comma-separated string."""
        return [o.strip() for o in self.api_cors_origins.split(",") if o.strip()]


# Global settings instance
settings = Settings()
