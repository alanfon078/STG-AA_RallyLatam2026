from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="STG_", env_file=".env", extra="ignore")

    serial_port: str | None = None
    serial_baud: int = 115200
    cluster_radius_m: float = 80.0
    cluster_window_min: int = 10


settings = Settings()
