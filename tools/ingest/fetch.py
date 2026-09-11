"""Ввічливий HTTP: власний User-Agent, robots.txt, Crawl-delay, умовний GET.

Правила з docs/event-ingestion.md, розділ 8, виконуються буквально, а не «за духом»:
джерело має бачити, хто до нього ходить, і мати змогу нас зупинити одним рядком у robots.txt.
"""
from __future__ import annotations

import gzip
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from dataclasses import dataclass

USER_AGENT = "PoruchBot/0.1 (+https://poruch.app/bot; contact@poruch.app)"

_robots_cache: dict[str, urllib.robotparser.RobotFileParser | None] = {}
_last_hit: dict[str, float] = {}


@dataclass
class Response:
    url: str
    status: int
    body: str
    etag: str | None = None
    last_modified: str | None = None

    @property
    def not_modified(self) -> bool:
        return self.status == 304


def _robots_for(url: str) -> urllib.robotparser.RobotFileParser | None:
    root = "{0.scheme}://{0.netloc}".format(urllib.parse.urlsplit(url))
    if root in _robots_cache:
        return _robots_cache[root]
    rp = urllib.robotparser.RobotFileParser()
    rp.set_url(root + "/robots.txt")
    try:
        req = urllib.request.Request(root + "/robots.txt", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=20) as r:
            rp.parse(r.read().decode("utf-8", "replace").splitlines())
    except Exception:
        # Недоступний robots.txt — не привід вважати, що все дозволено.
        rp = None
    _robots_cache[root] = rp
    return rp


def allowed(url: str) -> bool:
    rp = _robots_for(url)
    return bool(rp and rp.can_fetch(USER_AGENT, url))


def crawl_delay(url: str, default: float) -> float:
    rp = _robots_for(url)
    if not rp:
        return default
    try:
        d = rp.crawl_delay(USER_AGENT)
    except Exception:
        d = None
    return max(float(d), default) if d else default


def _throttle(url: str, delay: float) -> None:
    host = urllib.parse.urlsplit(url).netloc
    wait = delay - (time.monotonic() - _last_hit.get(host, 0.0))
    if wait > 0:
        time.sleep(wait)
    _last_hit[host] = time.monotonic()


def get(url: str, *, delay: float = 2.0, etag: str | None = None,
        last_modified: str | None = None, timeout: int = 60,
        check_robots: bool = True) -> Response:
    """Умовний GET. 304 повертається як є — це найдешевший запуск із можливих."""
    if check_robots and not allowed(url):
        raise PermissionError(f"robots.txt забороняє {url}")
    _throttle(url, crawl_delay(url, delay))

    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Encoding": "gzip",
        "Accept-Language": "uk,en;q=0.8",
    }
    if etag:
        headers["If-None-Match"] = etag
    if last_modified:
        headers["If-Modified-Since"] = last_modified

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            if r.headers.get("Content-Encoding") == "gzip":
                raw = gzip.decompress(raw)
            return Response(url, r.status, raw.decode("utf-8", "replace"),
                            r.headers.get("ETag"), r.headers.get("Last-Modified"))
    except urllib.error.HTTPError as e:
        if e.code == 304:
            return Response(url, 304, "", etag, last_modified)
        return Response(url, e.code, "")
    except Exception:
        return Response(url, 0, "")
