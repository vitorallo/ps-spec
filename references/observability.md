# Observability — logging conventions so AI and humans can debug

Every ps-spec change ships its logging with the code. The point is practical: when a test-plan row fails, the first move is to read the logs; when the on-call human gets paged, the first move is to read the logs; when a future session resumes an epic, it learns the runtime behavior from the logs. Code that is silent is code nobody can debug without stepping through it.

## Principles (stack-independent)

1. **Named loggers, one per module**, namespaced by feature: `app.tasks.api`, `app.tasks.store`, `worker.digest`. Lets you raise one feature to DEBUG without drowning in everything else.
2. **Log at boundaries**: entry and exit of request handlers / commands / jobs, every call to an external system (DB, HTTP, queue, model API) with its duration, and every error with context. Inside a function, log decisions, not every line.
3. **Structured fields, not prose**: `task.create id=… user=… duration_ms=…` (or JSON in services). Greppable, parseable, stable keys. Event names are dotted and lowercase: `task.create`, `task.create.failed`.
4. **Correlation id** on anything that spans steps: a request id for HTTP, a run id for jobs/CLIs, propagated into every log line of that flow. That's how one request is followed end-to-end.
5. **Levels mean something**: `DEBUG` internal detail (payloads, queries), `INFO` lifecycle and business events, `WARN` recoverable / expected failures (validation, retries), `ERROR` something broke and a human may need to act — always with the exception and the ids.
6. **One switch**: `LOG_LEVEL` (or `DEBUG=1`) env var read once at startup; default `INFO`; `DEBUG` in tests when a case fails.
7. **Two sinks**: stdout (containers, CI, the console tool) and a file under `logs/` for local runs (gitignored). Rotate the file if the app is long-running.
8. **Never swallow**: no empty `catch`, no `except: pass`, no `.catch(() => {})`. Log with context, then re-raise or return an explicit error.
9. **No secrets in logs**: redact tokens, passwords, full card numbers, and cap payload logging at DEBUG with truncation.
10. **Startup banner**: one INFO line at boot with version/commit, environment, log level, key config (non-secret). Its presence is E00's smoke test.
11. **Health + metrics where it's a service**: `/health` (liveness) and, if cheap, counters/durations for the main operations; a metric is a log line you can graph.

Write the feature's logging decisions in `design.md → Observability` during `plan`, implement them in the `Observability` task group during `code`, and verify them in `test-plan.md → Observability checks`.

## E00 deliverable: the logger module

E00 creates one module every later epic imports. Minimum surface: `get_logger(name)`, level from env, stdout + file handlers, a request/run id helper, and the startup banner. Everything below is a starting point — adapt to the stack the PRD chose.

### Python
`logging` from the stdlib is enough for most apps; `structlog` if JSON output is needed for a log aggregator.
```python
# app/logging_setup.py
import logging, os, sys, uuid, contextvars
from logging.handlers import RotatingFileHandler

run_id: contextvars.ContextVar[str] = contextvars.ContextVar("run_id", default="-")

class _Ctx(logging.Filter):
    def filter(self, record):
        record.run_id = run_id.get()
        return True

def configure(name="app", log_dir="logs"):
    level = os.getenv("LOG_LEVEL", "DEBUG" if os.getenv("DEBUG") else "INFO").upper()
    fmt = "%(asctime)s %(levelname)-5s %(name)s run=%(run_id)s %(message)s"
    handlers = [logging.StreamHandler(sys.stdout)]
    if log_dir:
        os.makedirs(log_dir, exist_ok=True)
        handlers.append(RotatingFileHandler(f"{log_dir}/{name}.log", maxBytes=5_000_000, backupCount=3))
    logging.basicConfig(level=level, format=fmt, datefmt="%Y-%m-%dT%H:%M:%S", handlers=handlers, force=True)
    for h in handlers: h.addFilter(_Ctx())
    for noisy in ("httpx", "httpcore", "urllib3"): logging.getLogger(noisy).setLevel(logging.WARNING)
    logging.getLogger(name).info("startup version=%s env=%s log_level=%s", os.getenv("APP_VERSION", "dev"), os.getenv("APP_ENV", "local"), level)

def new_run_id(): rid = uuid.uuid4().hex[:8]; run_id.set(rid); return rid
```
Usage: `log = logging.getLogger("app.tasks.api")` … `log.info("task.create id=%s duration_ms=%d", t.id, ms)`. Use `%s` args, not f-strings, so DEBUG lines cost nothing when off. For FastAPI, a middleware sets `new_run_id()` per request and adds `X-Request-Id` to the response.

### Node / TypeScript
`pino` (fast, JSON, child loggers) — `pino-pretty` for local readability.
```ts
// src/lib/log.ts
import pino from "pino";
import { AsyncLocalStorage } from "node:async_hooks";
export const als = new AsyncLocalStorage<{ reqId: string }>();
const level = process.env.LOG_LEVEL ?? (process.env.DEBUG ? "debug" : "info");
export const root = pino({
  level,
  mixin: () => ({ reqId: als.getStore()?.reqId ?? "-" }),
  transport: process.env.NODE_ENV === "production" ? undefined : { target: "pino-pretty" },
});
export const getLogger = (name: string) => root.child({ mod: name });
root.info({ version: process.env.APP_VERSION ?? "dev", env: process.env.NODE_ENV ?? "local", level }, "startup");
```
Usage: `const log = getLogger("app.tasks.api"); log.info({ event: "task.create", id, durationMs }, "task created")`. Express/Fastify: a middleware runs `als.run({ reqId }, next)` and sets `X-Request-Id`. Browser code: a tiny `debug`-style wrapper gated by `localStorage.DEBUG`, and never `console.log` left in production paths.

### Go
`log/slog` (stdlib): `slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: levelFromEnv()}))`, `logger.With("mod", "tasks.api")`, request id via `context.Context` and a middleware; `slog.Info("task.create", "id", id, "duration_ms", ms)`.

### Rust
`tracing` + `tracing-subscriber` with `EnvFilter::from_default_env()` (`RUST_LOG=app=debug`), `#[instrument]` on handlers for spans (that's your correlation id), `info!(event="task.create", id=%id, duration_ms=ms)`.

### Other stacks
Pick the idiomatic structured logger (Java: SLF4J + Logback with MDC for the request id; .NET: `ILogger` with scopes; Swift: `os.Logger` with subsystem/category; Elixir: `Logger` metadata). The eleven principles above are the contract; the library is a detail.

## What the on-call human and the AI both need in the feature doc

In `<docs-dir>/<feature>.md → Logs & debugging`: the logger names this feature uses, the 3–5 event names on the happy path, the events that mean trouble and what they usually indicate, how to turn on DEBUG for just this feature, where the file is, and which test-plan tool to use to reproduce a request. If a bug took more than ten minutes to find during `test`, add the log line that would have made it a one-minute find — that's the observability loop closing.
