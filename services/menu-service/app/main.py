import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request

from .config import load_settings
from .db import MenuRepository
from .logging_setup import setup_logging
from .routers import health, stalls

logger = logging.getLogger("menu-service")


def create_app() -> FastAPI:
    settings = load_settings()
    setup_logging(settings.log_level)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.repo = MenuRepository(
            table_name=settings.table_name,
            region=settings.aws_region,
            endpoint_url=settings.dynamodb_endpoint_url,
        )
        logger.info(
            "menu-service started",
            extra={"extra_fields": {"table": settings.table_name}},
        )
        yield

    app = FastAPI(title="MakanLah menu-service", version="0.1.0", lifespan=lifespan)

    @app.middleware("http")
    async def request_logging(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        logging.getLogger("request").info(
            "%s %s",
            request.method,
            request.url.path,
            extra={
                "extra_fields": {
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                }
            },
        )
        return response

    app.include_router(health.router)
    app.include_router(stalls.router)
    return app


app = create_app()
