from fastapi import APIRouter, HTTPException, Request

router = APIRouter(tags=["health"])


@router.get("/healthz")
def healthz() -> dict:
    """Liveness: process is up. No dependency checks."""
    return {"status": "ok"}


@router.get("/readyz")
def readyz(request: Request) -> dict:
    """Readiness: DynamoDB table reachable."""
    if request.app.state.repo.ping():
        return {"status": "ready"}
    raise HTTPException(status_code=503, detail="dependencies unavailable")
