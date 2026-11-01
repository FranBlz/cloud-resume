"""Smoke tests against the deployed site and API.

Skipped unless the URLs are set, e.g. in PowerShell:
    $env:API_URL  = terraform -chdir=infra output -raw api_url
    $env:SITE_URL = terraform -chdir=infra output -raw site_url
    pytest tests/smoke

Only GET and OPTIONS are sent, so running these never changes the count.
"""

import json
import os
import urllib.error
import urllib.request

import pytest

API_URL = os.environ.get("API_URL", "").rstrip("/")
SITE_URL = os.environ.get("SITE_URL", "").rstrip("/")

needs_api = pytest.mark.skipif(not API_URL, reason="API_URL not set")
needs_site = pytest.mark.skipif(not SITE_URL, reason="SITE_URL not set")


def request(url, method="GET", headers=None):
    req = urllib.request.Request(url, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, response.headers, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read().decode()


@needs_api
def test_api_returns_count():
    status, headers, body = request(f"{API_URL}/visits")

    assert status == 200
    assert headers["Content-Type"].startswith("application/json")
    count = json.loads(body)["count"]
    assert isinstance(count, int) and count >= 0


@needs_api
def test_api_rejects_unrouted_method():
    status, _, _ = request(f"{API_URL}/visits", method="DELETE")

    assert status == 404


@needs_api
def test_cors_blocks_other_origins():
    _, headers, _ = request(
        f"{API_URL}/visits",
        method="OPTIONS",
        headers={
            "Origin": "https://evil.example",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert headers.get("Access-Control-Allow-Origin") is None


@needs_api
@needs_site
def test_cors_allows_the_site():
    _, headers, _ = request(
        f"{API_URL}/visits",
        method="OPTIONS",
        headers={"Origin": SITE_URL, "Access-Control-Request-Method": "POST"},
    )

    assert headers.get("Access-Control-Allow-Origin") == SITE_URL


@needs_site
def test_site_serves_the_cv():
    status, headers, body = request(f"{SITE_URL}/")

    assert status == 200
    assert headers["Content-Type"].startswith("text/html")
    assert 'id="visitor-count"' in body
    assert "counter.js" in body


@needs_site
def test_site_serves_counter_script():
    status, _, body = request(f"{SITE_URL}/counter.js")

    assert status == 200
    assert "API_URL" in body


@needs_site
def test_missing_page_returns_404_page():
    status, _, body = request(f"{SITE_URL}/this-page-does-not-exist")

    assert status == 404
    assert "Content-Security-Policy" in body


@needs_site
def test_http_redirects_to_https():
    http_url = SITE_URL.replace("https://", "http://", 1)

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    try:
        opener.open(http_url, timeout=10)
        pytest.fail("HTTP request was served instead of redirected")
    except urllib.error.HTTPError as error:
        assert error.code in (301, 302, 307, 308)
        assert error.headers["Location"].startswith("https://")
