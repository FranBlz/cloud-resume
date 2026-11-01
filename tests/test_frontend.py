"""Static checks on frontend/ that catch deploy-breaking mistakes before
anything is uploaded. These live outside frontend/ because that whole folder
is synced to S3."""

import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

import pytest

FRONTEND_DIR = Path(__file__).resolve().parents[1] / "frontend"
PAGES = ["index.html", "404.html"]


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.csp = None
        self.ids = set()
        self.scripts = []
        self.local_refs = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if (
            tag == "meta"
            and attrs.get("http-equiv", "").lower() == "content-security-policy"
        ):
            self.csp = attrs.get("content", "")
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "script":
            self.scripts.append(attrs)
        for name in ("href", "src"):
            ref = attrs.get(name)
            if (
                ref
                and not urlparse(ref).scheme
                and not ref.startswith(("#", "//", "mailto:"))
            ):
                self.local_refs.append(ref)


def parse(page):
    parser = PageParser()
    parser.feed((FRONTEND_DIR / page).read_text(encoding="utf-8"))
    return parser


def csp_directives(csp):
    return {
        parts[0]: parts[1:] for parts in (d.split() for d in csp.split(";")) if parts
    }


def counter_api_url():
    source = (FRONTEND_DIR / "counter.js").read_text(encoding="utf-8")
    match = re.search(r'API_URL\s*=\s*"([^"]+)"', source)
    assert match, "API_URL constant not found in counter.js"
    return match.group(1)


def local_file(ref):
    """Map a site path to its file in frontend/, the way CloudFront would."""
    path = urlparse(ref).path.lstrip("/")
    if path == "" or path.endswith("/"):
        path += "index.html"
    return FRONTEND_DIR / path


@pytest.mark.parametrize("page", PAGES)
def test_page_has_locked_down_csp(page):
    csp = parse(page).csp

    assert csp, f"{page} has no Content-Security-Policy meta tag"
    directives = csp_directives(csp)
    assert directives["default-src"] == ["'none'"]
    assert "'unsafe-inline'" not in csp
    assert "'unsafe-eval'" not in csp


def test_csp_allows_the_counter_api():
    """If the API URL in counter.js changes, the CSP has to change with it,
    or the browser silently blocks the call."""
    api = urlparse(counter_api_url())
    connect_src = csp_directives(parse("index.html").csp)["connect-src"]

    assert api.scheme == "https"
    assert f"https://{api.netloc}" in connect_src


def test_counter_api_url_targets_visits_route():
    assert urlparse(counter_api_url()).path == "/visits"


def test_index_loads_counter_and_has_placeholder():
    page = parse("index.html")

    assert "visitor-count" in page.ids
    assert any(s.get("src") == "counter.js" and "defer" in s for s in page.scripts)


@pytest.mark.parametrize("page", PAGES)
def test_local_links_exist(page):
    missing = [ref for ref in parse(page).local_refs if not local_file(ref).is_file()]

    assert not missing, f"{page} references files that are not in frontend/: {missing}"
