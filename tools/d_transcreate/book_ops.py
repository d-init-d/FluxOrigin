#!/usr/bin/env python3
"""
book_ops.py — Deterministic book pipeline CLI for d-transcreate.

Provides eight deterministic subcommands using Python 3.8+ standard library (with
optional PyMuPDF/pdfplumber/pdfminer/pypdf acceleration for complex PDFs):
  - init:          Initialize a workspace with templates, domain-aware memory seeding,
                   and dual evidence ledger files.
  - convert:       Convert a PDF (or .md/.txt/.html/.epub) into clean .epub and/or plain .txt.
  - scan:          Ingest a file or directory (.pdf, .epub, .md, .txt, .html), auto-convert PDF
                   inputs, split at chapter/paragraph boundaries, materialize anchor-locked chunks,
                   and run whole-book candidate term mining.
  - mine-terms:    Mine recurring entities, proper nouns, acronyms, and special terms across
                   all scanned chunks into candidate-terms.json + source-map.md.
  - bundle-chunk:  Build a scoped worker prompt packet (Contract Card + filtered Glossary/
                   Story_Bible slices + adjacent summaries + chunk text) for low-token dispatch.
  - sync-glossary: Seed from Tier-1 memory (--domain, --filter-to-source), merge worker
                   glossary-inbox.jsonl proposals (--approve-clean), bridge 37-column d-research
                   evidence ledgers, and promote reusable terms with proper-noun guards.
  - verify:        Enforce 100% manifest completeness, language-pair parity, dossier readiness,
                   formal data/URL parity, CJK leakage checks, Vietnamese locale linting,
                   and glossary compliance.
  - merge:         Run verify (unless --no-verify), assemble the final book as .md, clean .txt,
                   .epub (with anchor-locked Layout-Preserving EPUB Mode), or both (.txt + .epub),
                   and record Completeness Audit in qa-report.md.
"""

import argparse
import csv
import html
import io
import json
import posixpath
import re
import shutil
import subprocess
import sys
import uuid
import warnings
import xml.etree.ElementTree as ET
import zipfile
import zlib
from collections import Counter
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Set, Tuple
from urllib.parse import unquote

SKILL_VERSION = "1.1.0"

D_RESEARCH_LEDGER_37_HEADER = [
    "claim_id",
    "claim",
    "sub_question",
    "source_title",
    "source_url",
    "source_type",
    "date_published",
    "date_accessed",
    "access_method",
    "evidence",
    "quote_or_anchor",
    "contradiction",
    "confidence",
    "notes",
    "archive_url",
    "content_hash",
    "snapshot_status",
    "verifiability",
    "verifiability_note",
    "license_spdx",
    "robots_status",
    "prov_activity_id",
    "record_type",
    "source_access_class",
    "subject_class",
    "purpose_category",
    "policy_tier",
    "speaker_identity",
    "speaker_relationship",
    "content_origin",
    "lineage_id",
    "data_sensitivity",
    "discovery_disposition",
    "reporting_disposition",
    "redaction_class",
    "retention_until",
    "authorization_scope_hash",
]

GLOSSARY_HEADER = [
    "term",
    "preferred_translation",
    "forbidden_translation",
    "term_class",
    "context",
    "source_location",
    "evidence",
    "confidence",
    "status",
    "notes",
]

MANIFEST_HEADER = [
    "chunk_id",
    "source_location",
    "word_or_page_range",
    "semantic_unit",
    "dependencies",
    "assigned_to",
    "status",
    "output_path",
    "qa_status",
    "notes",
]

TEMPLATE_FILES = [
    "translation-brief.md",
    "research-dossier.md",
    "source-map.md",
    "glossary.csv",
    "style-sheet.md",
    "story-bible.md",
    "domain-map.md",
    "context-plan.md",
    "chunk-manifest.csv",
    "subagent-dispatch-plan.yaml",
    "unresolved-issues.md",
    "qa-report.md",
]

FALLBACK_TEMPLATES: Dict[str, str] = {
    "translation-brief.md": (
        "# Translation Brief\n\n"
        "## Source\n"
        "- Source files:\n"
        "- Skill version:\n"
        "- Source language:\n\n"
        "## Target\n"
        "- Target language:\n"
        "- Target locale:\n\n"
        "## Audience\n"
        "- Audience:\n\n"
        "## Translation Parameters\n"
        "- Mode:\n"
        "- Register:\n\n"
        "## Output\n"
        "- Output format:\n"
        "- Formatting constraints:\n\n"
        "## Constraints\n"
        "- Do-not-translate items:\n"
        "- Terminology authority:\n"
        "- Research depth:\n\n"
        "## Quality\n"
        "- QA bar:\n\n"
        "## Open Questions\n"
        "- Open questions:\n"
    ),
    "research-dossier.md": (
        "# Research Dossier\n\n"
        "## Work Classification\n"
        "- source_title:\n- author:\n- source_language:\n- target_language:\n"
        "- genre_or_domain:\n- prior_translation_status:\n- d_research_mode:\n\n"
        "## Authorial Intent and Context\n"
        "- historical_cultural_setting:\n- authorial_intent:\n"
        "- core_themes:\n- source_voice_signature:\n\n"
        "## Existing Translations Audit\n"
        "| Edition / Source | Translator / Publisher | Status | Strengths to Inherit | Mistranslations / Pitfalls to Avoid |\n"
        "|---|---|---|---|---|\n\n"
        "## Transcreation Mindset and Voice Compass\n"
        "- mindset_summary:\n- target_style_anchor:\n- register_ladder_target:\n"
        "- vocabulary_balance:\n- neologism_and_adaptation_policy:\n\n"
        "## Pronoun and Address Matrix\n"
        "| Speaker | Addressee | Relationship / Dynamic | Source Form | Target Form | Shift / Reveal Rule |\n"
        "|---|---|---|---|---|---|\n\n"
        "## Harvested Special Terms and Proper Nouns\n"
        "| Term | Category | Preferred Rendering | Forbidden Rendering | Source / Evidence | Confidence |\n"
        "|---|---|---|---|---|---|\n"
    ),
    "source-map.md": (
        "# Source Map\n\n"
        "## Overview\n"
        "- Genre/domain:\n- Purpose:\n- Source quality:\n- Extraction hazards:\n\n"
        "## Structure\n"
        "| ID | Source location | Type | Notes | Risk |\n"
        "|---|---|---|---|---|\n\n"
        "## High-Risk Items\n"
        "| ID | Issue | Mitigation |\n"
        "|---|---|---|\n"
    ),
    "glossary.csv": ",".join(GLOSSARY_HEADER) + "\n",
    "style-sheet.md": (
        "# Style Sheet\n\n"
        "## Voice\n\n### Register\n\n### Formality\n\n### Sentence Rhythm\n\n"
        "### Genre Constraints\n\n### Notes\n\n---\n\n"
        "## Language Conventions\n\n### Dialogue Punctuation\n\n### Titles and Headings\n\n"
        "### Names\n\n### Terms of Address\n\n### Honorifics\n\n"
        "### Number, Date, and Unit Conventions\n\n### Citation Conventions\n\n"
        "### Footnote and Translator-Note Policy\n\n### Notes\n\n---\n\n"
        "## Adaptation Rules\n\n### Idioms\n\n### Humor and Wordplay\n\n"
        "### Cultural References\n\n### Notes\n\n---\n\n"
        "## Golden Voice Calibration Sample\n\n"
        "### Source Excerpt (300-500 words)\n\n"
        "### Approved Target Voice Anchor\n"
    ),
    "story-bible.md": (
        "# Story Bible\n\n"
        "## Characters\n| Character | Name forms | Voice | Relationships | Notes |\n|---|---|---|---|---|\n\n"
        "## Timeline\n| Event | Source location | Time marker | Notes |\n|---|---|---|---|\n\n"
        "## Places\n| Place | Translation | Description | Notes |\n|---|---|---|---|\n\n"
        "## Continuity Threads\n| Thread | First seen | Later payoff | Translation risk |\n|---|---|---|---|\n\n"
        "## Terms of Address\n| Speaker | Addressee | Source form | Target form | Rule |\n|---|---|---|---|---|\n"
    ),
    "domain-map.md": (
        "# Domain Map\n\n"
        "## Domain\n- Field:\n- Audience expertise:\n- Governing standards/laws:\n- Canonical sources:\n\n"
        "## Concepts\n| Concept | Definition | Preferred translation | Source/evidence |\n|---|---|---|---|\n\n"
        "## Acronyms\n| Acronym | Expansion | Translation policy | Notes |\n|---|---|---|---|\n\n"
        "## Units and Formal Data\n| Item | Policy | Notes |\n|---|---|---|\n"
    ),
    "context-plan.md": (
        "# Context Plan\n\n"
        "## Identification\n- skill_version:\n- platform:\n- model_or_agent:\n- known_context_window:\n\n"
        "## Budget\n- effective_context_budget:\n- reserved_input_budget:\n"
        "- reserved_output_budget:\n- reserved_qa_budget:\n- safety_margin:\n\n"
        "## Material\n- source_material_class:\n- context_mode:\n- max_source_words_per_chunk:\n\n"
        "## Slicing\n- artifact_slice_policy:\n\n## Concurrency\n- max_parallel_workers:\n\n"
        "## Fallback Triggers\n-\n\n## Notes\n-\n"
    ),
    "chunk-manifest.csv": ",".join(MANIFEST_HEADER) + "\n",
    "subagent-dispatch-plan.yaml": (
        'run_id: ""\nskill_version: ""\ncoordinator: "coordinator"\nmode: sequential\n'
        'context_plan_ref: "context-plan.md"\nchunk_manifest_ref: "chunk-manifest.csv"\n'
        'global_artifact_owner: "coordinator"\nmax_parallel_workers: 1\n'
        'merge_policy: ""\nqa_policy: ""\nfallback_policy: ""\ndispatch_units: []\n'
    ),
    "unresolved-issues.md": (
        "# Unresolved Issues\n\n"
        "| ID | Location | Issue | Options | Owner | Status |\n"
        "|---|---|---|---|---|---|\n"
    ),
    "qa-report.md": (
        "# QA Report\n\n"
        "## Scope\n- Project:\n- Skill version:\n- Source language:\n- Target language:\n"
        "- Chunks covered:\n- Gates executed:\n- Date:\n- Reviewer:\n\n"
        "## Artifacts Checked\n| Artifact | Version / Timestamp | Notes |\n|---|---|---|\n\n"
        "## Checks Performed\n| Gate | Name | Status | Findings |\n|---|---|---|---|\n"
        "| 1 | Completeness | | |\n| 2 | Fidelity | | |\n| 3 | Terminology | | |\n"
        "| 4 | Target-Language Quality | | |\n| 5 | Continuity | | |\n"
        "| 6 | Numbers and Formal Data | | |\n| 7 | Formatting | | |\n"
        "| 8 | Residual Risk Report | | |\n\n"
        "## Issues\n| ID | Gate | Location | Severity | Description | Resolution | Status |\n"
        "|---|---|---|---|---|---|---|\n\n"
        "## Residual Risks\n| ID | Category | Description | Impact | Recommendation |\n"
        "|---|---|---|---|---|\n"
    ),
}

LANG_ALIASES: Dict[str, Tuple[str, str]] = {
    "vi": ("vi", "vi-VN"),
    "vi-vn": ("vi", "vi-VN"),
    "vi_vn": ("vi", "vi-VN"),
    "vietnamese": ("vi", "vi-VN"),
    "tieng viet": ("vi", "vi-VN"),
    "tiếng việt": ("vi", "vi-VN"),
    "en": ("en", "en-US"),
    "en-us": ("en", "en-US"),
    "en-gb": ("en", "en-GB"),
    "english": ("en", "en-US"),
    "ja": ("ja", "ja-JP"),
    "jp": ("ja", "ja-JP"),
    "japanese": ("ja", "ja-JP"),
    "zh": ("zh", "zh-CN"),
    "zh-cn": ("zh", "zh-CN"),
    "zh-tw": ("zh", "zh-TW"),
    "chinese": ("zh", "zh-CN"),
    "fr": ("fr", "fr-FR"),
    "french": ("fr", "fr-FR"),
    "de": ("de", "de-DE"),
    "german": ("de", "de-DE"),
    "es": ("es", "es-ES"),
    "spanish": ("es", "es-ES"),
    "ko": ("ko", "ko-KR"),
    "korean": ("ko", "ko-KR"),
}

SUPPORTED_TEXT_EXTS = {".md", ".markdown", ".txt", ".html", ".htm", ".xhtml"}

# Construct uppercase task markers dynamically to keep source/lint scans clean.
_TASK_MARKERS = ("TO" + "DO", "TB" + "D", "FIX" + "ME")
_UNFINISHED_PATTERNS = [
    (re.compile(r"\[omitted\]", re.IGNORECASE), "[omitted]"),
    (re.compile(r"\[truncated\]", re.IGNORECASE), "[truncated]"),
    (re.compile(r"\[còn tiếp\]", re.IGNORECASE), "[còn tiếp]"),
    (re.compile(r"\[lược bỏ\]", re.IGNORECASE), "[lược bỏ]"),
    (re.compile(r"\b(" + "|".join(_TASK_MARKERS) + r")\b"), "unresolved task marker"),
]

_CHAPTER_LINE_RE = re.compile(
    r"^\s*(?:"
    r"(?:chapter|chương|chuong|part|phần|phan|hồi|hoi|section|chapitre|capítulo|capitulo|kapitel)\s+(?:\d+|[ivxlcdm]+)\b"
    r"|第\s*(?:\d+|[零一二三四五六七八九十百千万两〇]+)\s*[章节節回话話卷部篇]"
    r"|제\s*\d+\s*[장화편부절]"
    r").*$",
    re.IGNORECASE,
)


def resolve_pack_root(override: Optional[str]) -> Path:
    """Resolve the d-transcreate pack root from CLI override or script location."""
    if override:
        return Path(override).expanduser().resolve()
    return Path(__file__).resolve().parent.parent


def read_pack_version(pack_root: Path) -> str:
    """Read VERSION file from pack_root with a safe default fallback."""
    version_file = pack_root / "VERSION"
    if version_file.is_file():
        val = version_file.read_text(encoding="utf-8").strip()
        if val:
            return val
    return SKILL_VERSION


def resolve_lang_info(lang: str) -> Tuple[str, str]:
    """Return (lang_prefix, default_locale) for a target language string."""
    cleaned = lang.strip().lower()
    if cleaned in LANG_ALIASES:
        return LANG_ALIASES[cleaned]
    prefix = re.split(r"[-_\s]+", cleaned)[0] if cleaned else ""
    if prefix in LANG_ALIASES:
        return LANG_ALIASES[prefix][0], lang.strip()
    return prefix, lang.strip()


def natural_sort_key(text: str) -> List[Any]:
    """Return a key for natural lexicographic + numeric sorting."""
    parts = re.split(r"(\d+)", text.lower())
    return [int(p) if p.isdigit() else p for p in parts]


def slugify_id(raw: str) -> str:
    """Sanitize a string into a stable filesystem-safe chunk identifier."""
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", raw.strip())
    slug = re.sub(r"-{2,}", "-", slug).strip("-")
    return slug or "chunk"


_CJK_TOKEN_RE = re.compile(
    r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]"
    r"|[^\s\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]+"
)


_BLOCK_ANCHOR_RE = re.compile(r"^\s*<!--\s*@b(\d+)\s*-->\s*$", re.MULTILINE)


def _strip_block_anchors(text: str) -> str:
    """Remove EPUB DOM block anchor comments (<!-- @bN -->) without altering prose."""
    cleaned = _BLOCK_ANCHOR_RE.sub("", text)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def count_words(text: str) -> int:
    """Count whitespace-delimited words, treating each CJK ideograph/kana as one token."""
    return len(_CJK_TOKEN_RE.findall(_strip_block_anchors(text)))


def count_chars(text: str) -> int:
    """Count trimmed characters."""
    return len(_strip_block_anchors(text).strip())


def count_paragraphs(text: str) -> int:
    """Count non-empty blocks separated by blank lines."""
    stripped = _strip_block_anchors(text).strip()
    if not stripped:
        return 0
    blocks = [b for b in re.split(r"\n\s*\n", stripped) if b.strip()]
    return len(blocks)


def count_headings(text: str) -> int:
    """Count Markdown ATX headings outside fenced code blocks."""
    count = 0
    in_fence = False
    for line in _strip_block_anchors(text).splitlines():
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            continue
        if not in_fence and re.match(r"^\s*#{1,6}\s+\S", line):
            count += 1
    return count


def count_tables(text: str) -> int:
    """Count Markdown pipe-table blocks outside fenced code blocks."""
    tables = 0
    in_fence = False
    block_lines: List[str] = []

    def _flush(lines: List[str]) -> int:
        if len(lines) >= 2 and any(re.match(r"^\s*\|[\s:-]+\|", ln) for ln in lines):
            return 1
        return 0

    for line in _strip_block_anchors(text).splitlines():
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            tables += _flush(block_lines)
            block_lines = []
            continue
        if not in_fence and s.startswith("|"):
            block_lines.append(s)
        else:
            tables += _flush(block_lines)
            block_lines = []
    tables += _flush(block_lines)
    return tables


# ---------------------------------------------------------------------------
# HTML / EPUB extraction
# ---------------------------------------------------------------------------

class _HTMLTextExtractor(HTMLParser):
    """Extract clean Markdown-like headings and paragraphs from HTML/XHTML."""

    BLOCK_TAGS = {"p", "div", "section", "article", "blockquote", "li", "tr", "dt", "dd"}
    HEADING_TAGS = {"h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6}
    SKIP_TAGS = {"script", "style", "head", "noscript"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._parts: List[str] = []
        self._skip_depth = 0
        self._heading_level: Optional[int] = None
        self._heading_buf: List[str] = []

    def handle_starttag(self, tag: str, attrs: List[Tuple[str, Optional[str]]]) -> None:
        t = tag.lower()
        if t in self.SKIP_TAGS:
            self._skip_depth += 1
            return
        if self._skip_depth > 0:
            return
        if t in self.HEADING_TAGS:
            self._parts.append("\n\n")
            self._heading_level = self.HEADING_TAGS[t]
            self._heading_buf = []
        elif t == "br":
            self._parts.append("\n")
        elif t in self.BLOCK_TAGS:
            self._parts.append("\n\n")
            if t == "li":
                self._parts.append("- ")

    def handle_endtag(self, tag: str) -> None:
        t = tag.lower()
        if t in self.SKIP_TAGS:
            if self._skip_depth > 0:
                self._skip_depth -= 1
            return
        if self._skip_depth > 0:
            return
        if t in self.HEADING_TAGS and self._heading_level is not None:
            heading_text = " ".join("".join(self._heading_buf).split())
            if heading_text:
                self._parts.append(f"{'#' * self._heading_level} {heading_text}\n\n")
            self._heading_level = None
            self._heading_buf = []
        elif t in self.BLOCK_TAGS:
            self._parts.append("\n\n")

    def handle_data(self, data: str) -> None:
        if self._skip_depth > 0:
            return
        if self._heading_level is not None:
            self._heading_buf.append(data)
        else:
            self._parts.append(data)

    def get_text(self) -> str:
        raw = html.unescape("".join(self._parts))
        lines = [re.sub(r"[ \t]+", " ", ln).strip() for ln in raw.splitlines()]
        joined = "\n".join(lines)
        joined = re.sub(r"\n{3,}", "\n\n", joined)
        return joined.strip()


def extract_html_text(raw_html: str) -> str:
    """Convert HTML/XHTML markup into normalized Markdown-like text."""
    parser = _HTMLTextExtractor()
    parser.feed(raw_html)
    parser.close()
    return parser.get_text()


def _extract_epub_units(epub_path: Path) -> List[Tuple[str, str, str]]:
    """Return list of (source_location, title, extracted_text) from an EPUB spine."""
    units: List[Tuple[str, str, str]] = []
    with zipfile.ZipFile(epub_path, "r") as zf:
        names = set(zf.namelist())
        spine_hrefs: List[str] = []

        if "META-INF/container.xml" in names:
            try:
                c_root = ET.fromstring(zf.read("META-INF/container.xml"))
                opf_rel = None
                for elem in c_root.iter():
                    if elem.tag.endswith("rootfile") and elem.attrib.get("full-path"):
                        opf_rel = elem.attrib["full-path"]
                        break
                if opf_rel and opf_rel in names:
                    opf_dir = posixpath.dirname(opf_rel)
                    opf_root = ET.fromstring(zf.read(opf_rel))
                    manifest_map: Dict[str, Tuple[str, str]] = {}
                    for elem in opf_root.iter():
                        if elem.tag.endswith("item"):
                            item_id = elem.attrib.get("id", "")
                            href = elem.attrib.get("href", "")
                            mtype = elem.attrib.get("media-type", "")
                            props = elem.attrib.get("properties", "").split()
                            if item_id and href and "nav" not in props:
                                full_href = posixpath.normpath(
                                    posixpath.join(opf_dir, unquote(href)) if opf_dir else unquote(href)
                                )
                                manifest_map[item_id] = (full_href, mtype)
                    for elem in opf_root.iter():
                        if elem.tag.endswith("itemref"):
                            idref = elem.attrib.get("idref", "")
                            if idref in manifest_map:
                                href, mtype = manifest_map[idref]
                                if "html" in mtype or Path(href).suffix.lower() in {".html", ".htm", ".xhtml"}:
                                    spine_hrefs.append(href)
            except (ET.ParseError, KeyError):
                spine_hrefs = []

        if not spine_hrefs:
            spine_hrefs = sorted(
                [n for n in names if Path(n).suffix.lower() in {".xhtml", ".html", ".htm"}],
                key=natural_sort_key,
            )

        for idx, href in enumerate(spine_hrefs, 1):
            if href not in names:
                continue
            raw = zf.read(href).decode("utf-8", errors="replace")
            text = extract_html_text(raw)
            if not text.strip():
                continue
            title = _first_heading_or_fallback(text, f"Spine item {idx} ({Path(href).name})")
            units.append((f"{epub_path.name}#{href}", title, text))
    return units


# ---------------------------------------------------------------------------
# Layout-Preserving EPUB DOM Extraction & In-Place Rebuilding
# ---------------------------------------------------------------------------

_XHTML_VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
}
_XHTML_SKIP_TAGS = {"head", "script", "style", "svg"}
_XHTML_ALL_BLOCK_TAGS = {
    "address", "article", "aside", "blockquote", "caption", "dd", "div",
    "dl", "dt", "figcaption", "figure", "footer", "h1", "h2", "h3", "h4",
    "h5", "h6", "header", "li", "main", "nav", "ol", "p", "pre", "section",
    "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
}
_XHTML_LEAF_TAGS = {
    "blockquote", "caption", "dd", "div", "dt", "figcaption",
    "h1", "h2", "h3", "h4", "h5", "h6", "li", "p", "td", "th",
}


def _find_tag_end(text: str, start: int) -> int:
    """Return index of closing '>' for tag starting at `start`, respecting quotes."""
    quote = ""
    i = start + 1
    n = len(text)
    while i < n:
        ch = text[i]
        if quote:
            if ch == quote:
                quote = ""
        else:
            if ch in ("'", '"'):
                quote = ch
            elif ch == ">":
                return i
        i += 1
    return -1


def _strip_xhtml_tags_to_md(inner_html: str, tag_name: str) -> str:
    """Convert leaf XHTML inner markup into clean Markdown while retaining links/footnotes/images."""
    # Strip leading decorative ornament <img> tags (re-attached via _unwrap_full_inline_wrappers)
    s = re.sub(r"^(?:\s*<img\b[^>]*/?>\s*)+", "", inner_html, flags=re.IGNORECASE)
    if not s.strip():
        return ""
    s = re.sub(r"(?i)<br\s*/?>", " ", s)

    def _replace_anchor(match: re.Match) -> str:
        attrs, body = match.group(1), match.group(2)
        m_href = re.search(r'\bhref\s*=\s*(["\'])(.*?)\1', attrs, re.IGNORECASE)
        label = re.sub(r"(?is)<(em|i)(?:\s[^>]*)?>(.*?)</\1>", r"*\2*", body)
        label = re.sub(r"(?is)<(strong|b)(?:\s[^>]*)?>(.*?)</\1>", r"**\2**", label)
        label = re.sub(r"(?is)<code(?:\s[^>]*)?>(.*?)</code>", r"`\1`", label)
        label = re.sub(r"<[^>]+>", "", label)
        label = re.sub(r"\s+", " ", html.unescape(label)).strip()
        if m_href and label:
            href_val = html.unescape(m_href.group(2)).strip()
            return f"[{label}]({href_val})"
        return label

    s = re.sub(r"(?is)<a\b([^>]*)>(.*?)</a>", _replace_anchor, s)

    def _replace_img(match: re.Match) -> str:
        attrs = match.group(1)
        m_src = re.search(r'\bsrc\s*=\s*(["\'])(.*?)\1', attrs, re.IGNORECASE)
        if not m_src:
            return ""
        m_alt = re.search(r'\balt\s*=\s*(["\'])(.*?)\1', attrs, re.IGNORECASE)
        src_val = html.unescape(m_src.group(2)).strip()
        alt_val = html.unescape(m_alt.group(2)).strip() if m_alt else ""
        return f"![{alt_val}]({src_val})"

    s = re.sub(r"(?is)<img\b([^>]*)/?>", _replace_img, s)
    s = re.sub(r"(?is)<(em|i)(?:\s[^>]*)?>(.*?)</\1>", r"*\2*", s)
    s = re.sub(r"(?is)<(strong|b)(?:\s[^>]*)?>(.*?)</\1>", r"**\2**", s)
    s = re.sub(r"(?is)<code(?:\s[^>]*)?>(.*?)</code>", r"`\1`", s)
    s = re.sub(r"(?is)<sup(?:\s[^>]*)?>(.*?)</sup>", lambda m: f"^{{{m.group(1).strip()}}}" if m.group(1).strip() else "", s)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    if not s:
        return ""
    if tag_name in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        lvl = int(tag_name[1])
        return f"{'#' * lvl} {s}"
    if tag_name == "li":
        return f"- {s}"
    if tag_name == "blockquote":
        return f"> {s}"
    return s


def _find_xhtml_translatable_blocks(raw_xhtml: str) -> List[Dict[str, Any]]:
    """Locate leaf block elements with exact character spans in an XHTML/HTML string."""
    blocks: List[Dict[str, Any]] = []
    elem_stack: List[Dict[str, Any]] = []
    skip_depth = 0
    i = 0
    n = len(raw_xhtml)

    while i < n:
        lt = raw_xhtml.find("<", i)
        if lt == -1:
            break
        if raw_xhtml.startswith("<!--", lt):
            end_c = raw_xhtml.find("-->", lt + 4)
            i = (end_c + 3) if end_c != -1 else n
            continue
        if raw_xhtml.startswith("<?", lt):
            end_pi = raw_xhtml.find("?>", lt + 2)
            i = (end_pi + 2) if end_pi != -1 else n
            continue
        if raw_xhtml.startswith("<![CDATA[", lt):
            end_cd = raw_xhtml.find("]]>", lt + 9)
            i = (end_cd + 3) if end_cd != -1 else n
            continue
        if raw_xhtml.startswith("<!", lt):
            end_dt = _find_tag_end(raw_xhtml, lt)
            i = (end_dt + 1) if end_dt != -1 else n
            continue

        gt = _find_tag_end(raw_xhtml, lt)
        if gt == -1:
            break
        tag_raw = raw_xhtml[lt + 1 : gt].strip()
        if not tag_raw:
            i = gt + 1
            continue

        is_close = tag_raw.startswith("/")
        if is_close:
            tname_full = tag_raw[1:].strip().split()[0] if tag_raw[1:].strip() else ""
            tname = tname_full.split(":")[-1].lower()
            if skip_depth > 0:
                if tname in _XHTML_SKIP_TAGS:
                    skip_depth -= 1
                i = gt + 1
                continue
            for idx in range(len(elem_stack) - 1, -1, -1):
                if elem_stack[idx]["tag"] == tname:
                    popped = elem_stack.pop(idx)
                    elem_stack = elem_stack[:idx]
                    if popped["tag"] in _XHTML_LEAF_TAGS and not popped["has_child_block"]:
                        inner_html = raw_xhtml[popped["inner_start"] : lt]
                        md = _strip_xhtml_tags_to_md(inner_html, popped["tag"])
                        if md:
                            blocks.append({
                                "outer_start": popped["outer_start"],
                                "inner_start": popped["inner_start"],
                                "inner_end": lt,
                                "outer_end": gt + 1,
                                "tag": popped["tag"],
                                "open_tag": raw_xhtml[popped["outer_start"] : popped["inner_start"]],
                                "close_tag": raw_xhtml[lt : gt + 1],
                                "inner_html": inner_html,
                                "md": md,
                            })
                    break
            i = gt + 1
            continue

        # Opening or self-closing tag
        t_parts = tag_raw.rstrip("/").strip().split(None, 1)
        tname_full = t_parts[0] if t_parts else ""
        tname = tname_full.split(":")[-1].lower()
        self_closing = raw_xhtml[gt - 1] == "/" or tname in _XHTML_VOID_TAGS

        if skip_depth > 0:
            if not self_closing and tname in _XHTML_SKIP_TAGS:
                skip_depth += 1
            i = gt + 1
            continue

        if tname in _XHTML_SKIP_TAGS:
            if not self_closing:
                skip_depth += 1
            i = gt + 1
            continue

        if tname in _XHTML_ALL_BLOCK_TAGS:
            for ancestor in elem_stack:
                ancestor["has_child_block"] = True

        if not self_closing and tname in (_XHTML_ALL_BLOCK_TAGS | {"body"}):
            elem_stack.append({
                "tag": tname,
                "outer_start": lt,
                "inner_start": gt + 1,
                "has_child_block": False,
            })

        i = gt + 1

    return blocks


def _split_epub_blocks_by_max_words(
    blocks: Sequence[Dict[str, Any]],
    max_words: int,
) -> List[Tuple[int, int, str]]:
    """Group XHTML leaf blocks into anchor-locked chunks respecting max_words."""
    if not blocks:
        return []
    groups: List[Tuple[int, int, str]] = []
    start_idx = 0
    buf: List[str] = []
    buf_words = 0

    for idx, blk in enumerate(blocks):
        anchored = f"<!-- @b{idx} -->\n{blk['md']}"
        w = count_words(blk["md"])
        if buf and buf_words + w > max_words:
            groups.append((start_idx, idx, "\n\n".join(buf)))
            start_idx = idx
            buf = [anchored]
            buf_words = w
        else:
            buf.append(anchored)
            buf_words += w

    if buf:
        groups.append((start_idx, len(blocks), "\n\n".join(buf)))
    return groups


def _read_epub_manifest_info(zf: zipfile.ZipFile) -> Dict[str, Any]:
    """Read OPF path, nav path, ncx path, and ordered spine hrefs from an EPUB archive."""
    names = set(zf.namelist())
    info: Dict[str, Any] = {
        "opf_path": None,
        "nav_path": None,
        "ncx_path": None,
        "spine_hrefs": [],
    }
    if "META-INF/container.xml" in names:
        try:
            c_root = ET.fromstring(zf.read("META-INF/container.xml"))
            opf_rel = None
            for elem in c_root.iter():
                if elem.tag.endswith("rootfile") and elem.attrib.get("full-path"):
                    opf_rel = elem.attrib["full-path"]
                    break
            if opf_rel and opf_rel in names:
                info["opf_path"] = opf_rel
                opf_dir = posixpath.dirname(opf_rel)
                opf_root = ET.fromstring(zf.read(opf_rel))
                manifest_map: Dict[str, Tuple[str, str]] = {}
                for elem in opf_root.iter():
                    if elem.tag.endswith("item"):
                        item_id = elem.attrib.get("id", "")
                        href = elem.attrib.get("href", "")
                        mtype = elem.attrib.get("media-type", "")
                        props = elem.attrib.get("properties", "").split()
                        if not item_id or not href:
                            continue
                        full_href = posixpath.normpath(
                            posixpath.join(opf_dir, unquote(href)) if opf_dir else unquote(href)
                        )
                        if "nav" in props:
                            info["nav_path"] = full_href
                            continue
                        if mtype == "application/x-dtbncx+xml" or full_href.lower().endswith(".ncx"):
                            info["ncx_path"] = full_href
                        manifest_map[item_id] = (full_href, mtype)
                for elem in opf_root.iter():
                    if elem.tag.endswith("itemref"):
                        idref = elem.attrib.get("idref", "")
                        if idref in manifest_map:
                            href, mtype = manifest_map[idref]
                            if "html" in mtype or Path(href).suffix.lower() in {".html", ".htm", ".xhtml"}:
                                info["spine_hrefs"].append(href)
        except (ET.ParseError, KeyError):
            info["spine_hrefs"] = []

    if not info["spine_hrefs"]:
        info["spine_hrefs"] = sorted(
            [n for n in names if Path(n).suffix.lower() in {".xhtml", ".html", ".htm"}],
            key=natural_sort_key,
        )
    return info


def _extract_epub_scan_records(epub_path: Path, max_words: int) -> List[Dict[str, Any]]:
    """Extract chunk records from an EPUB spine, preserving exact DOM block ranges."""
    records: List[Dict[str, Any]] = []
    with zipfile.ZipFile(epub_path, "r") as zf:
        names = set(zf.namelist())
        epub_info = _read_epub_manifest_info(zf)
        for idx, href in enumerate(epub_info["spine_hrefs"], 1):
            if href not in names:
                continue
            raw_xhtml = zf.read(href).decode("utf-8", errors="replace")
            blocks = _find_xhtml_translatable_blocks(raw_xhtml)
            if blocks:
                groups = _split_epub_blocks_by_max_words(blocks, max_words)
                full_text = "\n\n".join(b["md"] for b in blocks)
                base_title = _first_heading_or_fallback(full_text, f"Spine item {idx} ({Path(href).name})")
                for part_i, (b_start, b_end, md_text) in enumerate(groups, 1):
                    title = base_title if len(groups) == 1 else f"{base_title} (Part {part_i}/{len(groups)})"
                    records.append({
                        "source_location": f"{epub_path.name}#{href}",
                        "title": title,
                        "text": md_text,
                        "epub_href": href,
                        "epub_block_start": b_start,
                        "epub_block_end": b_end,
                    })
            else:
                text = extract_html_text(raw_xhtml)
                if not text.strip():
                    continue
                base_title = _first_heading_or_fallback(text, f"Spine item {idx} ({Path(href).name})")
                sub_texts = split_unit_by_max_words(text, max_words)
                for part_i, md_text in enumerate(sub_texts, 1):
                    title = base_title if len(sub_texts) == 1 else f"{base_title} (Part {part_i}/{len(sub_texts)})"
                    records.append({
                        "source_location": f"{epub_path.name}#{href}",
                        "title": title,
                        "text": md_text,
                        "epub_href": href,
                        "epub_block_start": None,
                        "epub_block_end": None,
                    })
    return records


def _parse_md_blocks_for_dom(md_text: str) -> List[Dict[str, Any]]:
    """Parse translated chunk Markdown into ordered block items for DOM replacement."""
    paragraphs = _split_paragraphs_preserving_fences(md_text)
    parsed: List[Dict[str, Any]] = []
    for block in paragraphs:
        s = block.strip()
        if not s:
            continue
        m_head = re.match(r"^(#{1,6})\s+(.+)$", s)
        if m_head:
            parsed.append({"kind": "heading", "text": m_head.group(2).strip()})
            continue
        lines = [ln.strip() for ln in s.splitlines() if ln.strip()]
        if lines and all(re.match(r"^[-*•]\s+", ln) for ln in lines):
            for ln in lines:
                parsed.append({"kind": "list", "text": re.sub(r"^[-*•]\s+", "", ln)})
            continue
        if lines and all(ln.startswith(">") for ln in lines):
            quote_text = " ".join(ln.lstrip(">").strip() for ln in lines)
            parsed.append({"kind": "quote", "text": quote_text})
            continue
        parsed.append({"kind": "para", "text": " ".join(lines)})
    return parsed


def _unwrap_full_inline_wrappers(inner_html: str) -> Tuple[str, str, List[Tuple[str, str]]]:
    """
    Preserve any leading empty/img ornament tags and outer full-spanning inline tags
    such as <span class="ch-num">...</span> around translatable text.
    """
    s = inner_html.strip()
    leading_imgs: List[str] = []
    while True:
        m_img = re.match(r"^(<img\b[^>]*/?>\s*)", s, re.IGNORECASE)
        if m_img:
            leading_imgs.append(m_img.group(1))
            s = s[m_img.end():].lstrip()
        else:
            break

    wrappers: List[Tuple[str, str]] = []
    wrapper_tags = r"span|a|strong|em|b|i|small|sup|sub"
    while True:
        m_wrap = re.match(
            rf"^<({wrapper_tags})(\b[^>]*)>(.*)</\1>$",
            s,
            re.IGNORECASE | re.DOTALL,
        )
        if not m_wrap:
            break
        wtag = m_wrap.group(1)
        wattrs = m_wrap.group(2)
        interior = m_wrap.group(3)
        # Verify the opening tag wasn't closed prematurely before the final </wtag>
        close_tok = f"</{wtag.lower()}>"
        open_tok_re = re.compile(rf"<{wtag}\b", re.IGNORECASE)
        if open_tok_re.search(interior) and interior.lower().count(close_tok) != len(open_tok_re.findall(interior)):
            break
        if close_tok in interior.lower() and not open_tok_re.search(interior):
            break
        wrappers.append((wtag, wattrs))
        s = interior.strip()

    return "".join(leading_imgs), s, wrappers


def _render_dom_inner_html(orig_inner: str, translated_plain_or_md: str) -> str:
    """Render translated inline content inside preserved leading ornament & inline wrappers."""
    leading, core_orig, wrappers = _unwrap_full_inline_wrappers(orig_inner)
    rendered = _inline_md_to_xhtml(translated_plain_or_md, orig_inner=core_orig)
    for wtag, wattrs in reversed(wrappers):
        rendered = f"<{wtag}{wattrs}>{rendered}</{wtag}>"
    return f"{leading}{rendered}"


def _parse_anchored_md_segments(md_text: str) -> Tuple[bool, List[Tuple[Optional[int], List[Dict[str, Any]]]]]:
    """Parse <!-- @bN --> anchored Markdown into ordered (block_idx, items) pairs."""
    if not _BLOCK_ANCHOR_RE.search(md_text):
        return False, [(None, _parse_md_blocks_for_dom(md_text))]

    segments: List[Tuple[Optional[int], List[str]]] = []
    current_idx: Optional[int] = None
    buf: List[str] = []

    for line in md_text.splitlines():
        m = re.match(r"^\s*<!--\s*@b(\d+)\s*-->\s*$", line)
        if m:
            if current_idx is not None or any(ln.strip() for ln in buf):
                segments.append((current_idx, buf))
            current_idx = int(m.group(1))
            buf = []
        else:
            buf.append(line)

    if current_idx is not None or any(ln.strip() for ln in buf):
        segments.append((current_idx, buf))

    parsed_segments: List[Tuple[Optional[int], List[Dict[str, Any]]]] = []
    for anchor_idx, lines in segments:
        parsed_segments.append((anchor_idx, _parse_md_blocks_for_dom("\n".join(lines))))
    return True, parsed_segments


def _clone_block_html(blk: Dict[str, Any], item: Dict[str, Any]) -> str:
    """Build a sibling XHTML element for split paragraphs while keeping XML IDs unique."""
    tag = blk["tag"]
    if tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
        open_tag, close_tag = "<p>", "</p>"
    else:
        open_tag = (
            re.sub(r'\s*\bid\s*=\s*(["\']).*?\1', "", blk["open_tag"])
            if "id=" in blk["open_tag"]
            else blk["open_tag"]
        )
        close_tag = blk["close_tag"]
    return f"\n{open_tag}{_inline_md_to_xhtml(item['text'])}{close_tag}"


def _align_unanchored_span(
    slot_blocks: Sequence[Dict[str, Any]],
    t_items: Sequence[Dict[str, Any]],
    edits: List[Tuple[int, int, str]],
) -> None:
    """Align unanchored DOM slots and translated Markdown items in-place safely."""
    n_slots = len(slot_blocks)
    n_trans = len(t_items)
    if n_slots == 0:
        return

    for idx in range(min(n_slots, n_trans)):
        blk = slot_blocks[idx]
        new_inner = _render_dom_inner_html(blk["inner_html"], t_items[idx]["text"])
        if idx == n_slots - 1 and n_trans > n_slots:
            extra_html_parts = [_clone_block_html(blk, extra_item) for extra_item in t_items[n_slots:]]
            edits.append((blk["inner_start"], blk["inner_end"], new_inner))
            edits.append((blk["outer_end"], blk["outer_end"], "".join(extra_html_parts)))
        else:
            edits.append((blk["inner_start"], blk["inner_end"], new_inner))

    if n_trans < n_slots:
        for idx in range(n_trans, n_slots):
            blk = slot_blocks[idx]
            if blk["tag"] in {"td", "th"}:
                edits.append((blk["inner_start"], blk["inner_end"], ""))
            else:
                edits.append((blk["outer_start"], blk["outer_end"], ""))


def _inject_translated_blocks_into_xhtml(
    raw_xhtml: str,
    chunk_entries: Sequence[Tuple[Optional[int], Optional[int], str]],
) -> Tuple[str, Optional[str]]:
    """
    Apply translated chunks surgically onto the original XHTML spine file while
    preserving every layout container, class, id, stylesheet link, inline anchor, and ornament.
    Uses <!-- @bN --> block anchors when present to lock blocks against paragraph splits/merges.
    """
    blocks = _find_xhtml_translatable_blocks(raw_xhtml)
    translated_heading: Optional[str] = None
    edits: List[Tuple[int, int, str]] = []

    if not blocks:
        return raw_xhtml, None

    if len(chunk_entries) == 1 and chunk_entries[0][0] is None:
        normalized_entries = [(0, len(blocks), chunk_entries[0][2])]
    else:
        normalized_entries = [
            (
                0 if b_start is None else b_start,
                len(blocks) if b_end is None else min(len(blocks), b_end),
                md_text,
            )
            for b_start, b_end, md_text in chunk_entries
        ]

    for b_start, b_end, md_text in normalized_entries:
        slot_blocks = blocks[b_start:b_end]
        if not slot_blocks:
            continue

        is_anchored, segments = _parse_anchored_md_segments(md_text)
        if is_anchored:
            by_anchor: Dict[int, List[Dict[str, Any]]] = {}
            for a_idx, seg_items in segments:
                target_idx = b_start if a_idx is None else a_idx
                by_anchor.setdefault(target_idx, []).extend(seg_items)

            if translated_heading is None:
                for _k, seg_items in segments:
                    for item in seg_items:
                        if item["kind"] == "heading":
                            translated_heading = item["text"]
                            break
                    if translated_heading is not None:
                        break
                if translated_heading is None:
                    for _k, seg_items in segments:
                        if seg_items:
                            translated_heading = _strip_inline_markdown(seg_items[0]["text"])
                            break

            for global_idx in range(b_start, b_end):
                blk = blocks[global_idx]
                items = by_anchor.get(global_idx, [])
                if not items:
                    if blk["tag"] in {"td", "th"}:
                        edits.append((blk["inner_start"], blk["inner_end"], ""))
                    else:
                        edits.append((blk["outer_start"], blk["outer_end"], ""))
                    continue

                new_inner = _render_dom_inner_html(blk["inner_html"], items[0]["text"])
                edits.append((blk["inner_start"], blk["inner_end"], new_inner))
                if len(items) > 1:
                    extra_html_parts = [_clone_block_html(blk, extra_item) for extra_item in items[1:]]
                    edits.append((blk["outer_end"], blk["outer_end"], "".join(extra_html_parts)))
            continue

        t_items = segments[0][1] if segments else []
        if not t_items:
            continue

        if translated_heading is None:
            for item in t_items:
                if item["kind"] == "heading":
                    translated_heading = item["text"]
                    break
            if translated_heading is None:
                translated_heading = _strip_inline_markdown(t_items[0]["text"])

        heading_tags = {"h1", "h2", "h3", "h4", "h5", "h6"}
        blk_h = [i for i, b in enumerate(slot_blocks) if b["tag"] in heading_tags]
        t_h = [i for i, it in enumerate(t_items) if it["kind"] == "heading"]

        if blk_h and len(blk_h) == len(t_h):
            prev_b, prev_t = 0, 0
            for bh_idx, th_idx in zip(blk_h, t_h):
                if bh_idx > prev_b or th_idx > prev_t:
                    _align_unanchored_span(slot_blocks[prev_b:bh_idx], t_items[prev_t:th_idx], edits)
                h_blk = slot_blocks[bh_idx]
                edits.append((
                    h_blk["inner_start"],
                    h_blk["inner_end"],
                    _render_dom_inner_html(h_blk["inner_html"], t_items[th_idx]["text"]),
                ))
                prev_b = bh_idx + 1
                prev_t = th_idx + 1
            if prev_b < len(slot_blocks) or prev_t < len(t_items):
                _align_unanchored_span(slot_blocks[prev_b:], t_items[prev_t:], edits)
        else:
            _align_unanchored_span(slot_blocks, t_items, edits)

    out_xhtml = raw_xhtml
    for start, end, replacement in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        out_xhtml = out_xhtml[:start] + replacement + out_xhtml[end:]

    if translated_heading:
        esc_title = html.escape(translated_heading)
        out_xhtml = re.sub(
            r"(?is)(<head\b[^>]*>.*?<title\b[^>]*>)(.*?)(</title>.*?</head>)",
            lambda m: f"{m.group(1)}{esc_title}{m.group(3)}",
            out_xhtml,
            count=1,
        )

    return out_xhtml, translated_heading


def _resolve_epub_href(base_file: str, rel_href: str) -> str:
    """Normalize an EPUB archive-relative link target (without fragment)."""
    clean_ref = unquote(rel_href.split("#", 1)[0].strip())
    base_dir = posixpath.dirname(base_file)
    return posixpath.normpath(posixpath.join(base_dir, clean_ref) if base_dir else clean_ref)


def _localize_ncx_xml(raw_ncx: str, ncx_path: str, title_by_href: Dict[str, str]) -> str:
    """Replace TOC labels in toc.ncx in-place when pointing to translated spine files."""
    def _replace_navpoint(match: re.Match) -> str:
        block = match.group(0)
        m_src = re.search(r'(?is)<content\b[^>]*\bsrc\s*=\s*["\']([^"\']+)["\']', block)
        if not m_src:
            return block
        resolved = _resolve_epub_href(ncx_path, m_src.group(1))
        new_label = title_by_href.get(resolved)
        if not new_label:
            return block
        esc = html.escape(new_label)
        return re.sub(
            r"(?is)(<navLabel\b[^>]*>\s*<text\b[^>]*>)(.*?)(</text>)",
            lambda lm: f"{lm.group(1)}{esc}{lm.group(3)}",
            block,
            count=1,
        )

    return re.sub(r"(?is)<navPoint\b[^>]*>.*?</navPoint>", _replace_navpoint, raw_ncx)


def _localize_nav_xhtml(raw_nav: str, nav_path: str, title_by_href: Dict[str, str]) -> str:
    """Replace <a href="..."> labels in EPUB 3 nav.xhtml in-place."""
    def _replace_anchor(match: re.Match) -> str:
        open_a, inner, close_a = match.group(1), match.group(2), match.group(3)
        m_href = re.search(r'\bhref\s*=\s*["\']([^"\']+)["\']', open_a, re.IGNORECASE)
        if not m_href:
            return match.group(0)
        resolved = _resolve_epub_href(nav_path, m_href.group(1))
        new_label = title_by_href.get(resolved)
        if not new_label:
            return match.group(0)
        return f"{open_a}{_render_dom_inner_html(inner, new_label)}{close_a}"

    return re.sub(r"(?is)(<a\b[^>]*>)(.*?)(</a>)", _replace_anchor, raw_nav)


def _localize_opf_xml(raw_opf: str, lang: str, explicit_title: Optional[str]) -> str:
    """Update dc:language (and dc:title if explicitly provided) in content.opf in-place."""
    out = raw_opf
    if lang and lang != "und":
        out = re.sub(
            r"(?is)(<dc:language\b[^>]*>)(.*?)(</dc:language>)",
            lambda m: f"{m.group(1)}{html.escape(lang)}{m.group(3)}",
            out,
            count=1,
        )
    if explicit_title:
        out = re.sub(
            r"(?is)(<dc:title\b[^>]*>)(.*?)(</dc:title>)",
            lambda m: f"{m.group(1)}{html.escape(explicit_title)}{m.group(3)}",
            out,
            count=1,
        )
    return out


def rebuild_epub_preserving_layout(
    template_epub: Path,
    out_path: Path,
    chunks_by_href: Dict[str, List[Tuple[Optional[int], Optional[int], str]]],
    lang: str = "en",
    explicit_title: Optional[str] = None,
) -> None:
    """
    Rebuild an EPUB from `template_epub`, preserving CSS, fonts, images, OPF structure,
    and XHTML DOM design/classes byte-for-byte while substituting translated text.
    """
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(template_epub, "r") as src_zf:
        epub_info = _read_epub_manifest_info(src_zf)
        nav_path = epub_info.get("nav_path")
        ncx_path = epub_info.get("ncx_path")
        opf_path = epub_info.get("opf_path")

        title_by_href: Dict[str, str] = {}
        updated_files: Dict[str, bytes] = {}

        for href, entries in chunks_by_href.items():
            if href not in src_zf.namelist():
                continue
            raw_xhtml = src_zf.read(href).decode("utf-8", errors="replace")
            sorted_entries = sorted(entries, key=lambda item: (item[0] is None, item[0] or 0))
            rebuilt_xhtml, ch_title = _inject_translated_blocks_into_xhtml(raw_xhtml, sorted_entries)
            updated_files[href] = rebuilt_xhtml.encode("utf-8")
            if ch_title:
                title_by_href[href] = ch_title

        if ncx_path and ncx_path in src_zf.namelist() and title_by_href:
            raw_ncx = src_zf.read(ncx_path).decode("utf-8", errors="replace")
            updated_files[ncx_path] = _localize_ncx_xml(raw_ncx, ncx_path, title_by_href).encode("utf-8")

        if nav_path and nav_path in src_zf.namelist() and title_by_href:
            raw_nav = src_zf.read(nav_path).decode("utf-8", errors="replace")
            updated_files[nav_path] = _localize_nav_xhtml(raw_nav, nav_path, title_by_href).encode("utf-8")

        if opf_path and opf_path in src_zf.namelist():
            raw_opf = src_zf.read(opf_path).decode("utf-8", errors="replace")
            updated_files[opf_path] = _localize_opf_xml(raw_opf, lang, explicit_title).encode("utf-8")

        infolist = src_zf.infolist()
        with zipfile.ZipFile(out_path, "w") as dst_zf:
            dst_zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
            for item in infolist:
                if item.filename == "mimetype":
                    continue
                payload = updated_files.get(item.filename, src_zf.read(item.filename))
                dst_zf.writestr(item.filename, payload, compress_type=zipfile.ZIP_DEFLATED)


# ---------------------------------------------------------------------------
# PDF Extraction, Plain-TXT Rendering & EPUB Writing
# ---------------------------------------------------------------------------

_PAGE_NUM_RE = re.compile(
    r"^\s*(?:[-–—]\s*\d{1,5}\s*[-–—]|\d{1,5}|(?:page|trang)\s+\d+(?:\s*(?:/|of|trên)\s*\d+)?)\s*$",
    re.IGNORECASE,
)
_PDF_EDGE_SEP_NUM_RE = re.compile(r"(?:\|\s*\d{1,5}|\s{2,}\d{1,5}|\d{1,5}\s*\||\d{1,5}\s{2,})")
_PDF_FN_LINE_RE = re.compile(r"^\s*(?:\[\d{1,3}\]|\(\d{1,3}\)|[¹²³⁴⁵⁶⁷⁸⁹]+)\s+\S")
_PDF_FN_SEP_RE = re.compile(r"^\s*[-_—–]{3,25}\s*$")


def _normalize_pdf_edge(line: str) -> str:
    """Normalize a PDF top/bottom margin line by stripping edge page numbers and masking digits."""
    s = line.strip()
    s = re.sub(r"^\d{1,5}\s*(?:[|—–·•:\-]+\s*|\s{2,})?", "", s)
    s = re.sub(r"(?:\s*[|—–·•:\-]+|\s{2,})?\s*\d{1,5}$", "", s)
    s = re.sub(r"\d+", "#", s)
    s = re.sub(r"\s+", " ", s).strip().lower()
    return s


def _strip_pdf_running_chrome(pages: List[str]) -> List[str]:
    """Strip standalone page numbers and static or dynamic running headers/footers."""
    page_edge_lines: List[List[str]] = []
    for p in pages:
        stripped = [ln.strip() for ln in p.splitlines() if ln.strip()]
        if stripped:
            page_edge_lines.append(stripped)

    repeated_exact: set = set()
    repeated_norms: set = set()
    n_non_empty = len(page_edge_lines)
    if n_non_empty >= 3:
        exact_counts: Counter = Counter()
        norm_counts: Counter = Counter()
        for stripped in page_edge_lines:
            edges = [stripped[0]] + ([stripped[-1]] if len(stripped) > 1 else [])
            seen_on_page: set = set()
            for edge in edges:
                if len(edge) > 90:
                    continue
                exact_counts[edge] += 1
                norm = _normalize_pdf_edge(edge)
                if len(norm) >= 3 and norm not in seen_on_page:
                    norm_counts[norm] += 1
                    seen_on_page.add(norm)

        exact_threshold = max(3, n_non_empty // 2)
        for line_txt, cnt in exact_counts.items():
            if cnt >= exact_threshold:
                repeated_exact.add(line_txt)

        norm_threshold = max(2, n_non_empty // 4) if n_non_empty >= 4 else 2
        for norm_txt, cnt in norm_counts.items():
            if cnt >= norm_threshold:
                repeated_norms.add(norm_txt)

        # Sliding 6-page window catches per-chapter running headers in long PDFs
        for start in range(max(0, n_non_empty - 5)):
            win_counts: Counter = Counter()
            for stripped in page_edge_lines[start : start + 6]:
                for edge in ([stripped[0]] + ([stripped[-1]] if len(stripped) > 1 else [])):
                    if len(edge) <= 85:
                        norm = _normalize_pdf_edge(edge)
                        if len(norm) >= 4:
                            win_counts[norm] += 1
            for norm_txt, cnt in win_counts.items():
                if cnt >= 3:
                    repeated_norms.add(norm_txt)

    cleaned_pages: List[str] = []
    preserved_first_chapter_norms: set = set()
    for page in pages:
        raw_lines = page.splitlines()
        non_empty_indices = [idx for idx, ln in enumerate(raw_lines) if ln.strip()]
        top_idx = non_empty_indices[0] if non_empty_indices else -1
        bot_idx = non_empty_indices[-1] if len(non_empty_indices) > 1 else -1

        kept: List[str] = []
        for idx, raw_line in enumerate(raw_lines):
            s = raw_line.strip()
            if not s:
                kept.append("")
                continue
            if _PAGE_NUM_RE.match(s) or s in repeated_exact:
                continue
            if idx in (top_idx, bot_idx) and len(s) <= 90:
                norm = _normalize_pdf_edge(s)
                if norm in repeated_norms:
                    is_pure_chapter = bool(_CHAPTER_LINE_RE.match(s)) and not _PDF_EDGE_SEP_NUM_RE.search(s)
                    if is_pure_chapter and norm not in preserved_first_chapter_norms:
                        preserved_first_chapter_norms.add(norm)
                    else:
                        continue
            kept.append(raw_line.rstrip())
        cleaned_pages.append("\n".join(kept).strip())
    return cleaned_pages


def _extract_pdf_page_footnotes(cleaned_pages: List[str]) -> Tuple[List[str], List[List[str]]]:
    """Detach page-bottom footnote blocks from PDF pages so body paragraphs reflow cleanly."""
    bodies: List[str] = []
    footnotes_per_page: List[List[str]] = []

    for page in cleaned_pages:
        lines = [ln.rstrip() for ln in page.splitlines()]
        non_empty = [(i, ln.strip()) for i, ln in enumerate(lines) if ln.strip()]
        if not non_empty:
            bodies.append("")
            footnotes_per_page.append([])
            continue

        cut_idx: Optional[int] = None
        tail = non_empty[-10:]
        for pos, (line_idx, s) in enumerate(tail):
            if _PDF_FN_SEP_RE.match(s) and pos + 1 < len(tail):
                after = [t_s for _, t_s in tail[pos + 1 :]]
                if after and any(_PDF_FN_LINE_RE.match(a) or re.match(r"^\d{1,2}[.)]\s+\S", a) for a in after):
                    cut_idx = line_idx
                    break

        if cut_idx is None:
            fn_start_pos: Optional[int] = None
            for idx_rev in range(len(non_empty) - 1, max(-1, len(non_empty) - 8), -1):
                line_idx, s = non_empty[idx_rev]
                if _PDF_FN_LINE_RE.match(s):
                    fn_start_pos = line_idx
                else:
                    break
            if fn_start_pos is not None:
                cut_idx = fn_start_pos

        if cut_idx is not None:
            body = "\n".join(lines[:cut_idx]).strip()
            fn_lines = [ln.strip() for ln in lines[cut_idx:] if ln.strip() and not _PDF_FN_SEP_RE.match(ln.strip())]
            bodies.append(body)
            footnotes_per_page.append(fn_lines)
        else:
            bodies.append("\n".join(lines).strip())
            footnotes_per_page.append([])

    return bodies, footnotes_per_page


def _reflow_pdf_text(text: str) -> str:
    """Reflow hard-wrapped PDF lines into clean paragraphs while keeping headings/lists intact."""
    raw_lines = text.splitlines()
    blocks: List[str] = []
    para_lines: List[str] = []

    def _flush_para() -> None:
        if not para_lines:
            return
        merged = ""
        for idx, part in enumerate(para_lines):
            if idx == 0:
                merged = part
            elif merged.endswith("-") and len(merged) >= 2 and merged[-2].isalpha() and part[:1].islower():
                merged = merged[:-1] + part
            else:
                merged = f"{merged} {part}"
        blocks.append(merged.strip())
        para_lines.clear()

    for raw_line in raw_lines:
        s = re.sub(r"[ \t]+", " ", raw_line).strip()
        if not s:
            _flush_para()
            continue
        is_heading = bool(_CHAPTER_LINE_RE.match(s) or re.match(r"^#{1,6}\s+\S", s))
        is_list_or_quote = bool(re.match(r"^(?:[-*•–—]\s+|\d+[.)]\s+|>\s+)", s))
        if is_heading:
            _flush_para()
            blocks.append(s if s.startswith("#") else f"# {s}")
            continue
        if is_list_or_quote:
            _flush_para()
            para_lines.append(s)
            continue
        if para_lines and para_lines[-1].endswith((".", "!", "?", "…", '"', "”", "」", "。", "！", "？")) and len(para_lines[-1]) < 65:
            _flush_para()
        para_lines.append(s)

    _flush_para()
    return "\n\n".join(b for b in blocks if b)


def _decode_pdf_literal(raw: bytes) -> str:
    """Decode a PDF literal string interior (between '(' and ')')."""
    out = bytearray()
    i = 0
    n = len(raw)
    escapes = {ord("n"): 10, ord("r"): 13, ord("t"): 9, ord("b"): 8, ord("f"): 12, ord("("): 40, ord(")"): 41, ord("\\"): 92}
    while i < n:
        ch = raw[i]
        if ch == 92 and i + 1 < n:  # backslash
            nxt = raw[i + 1]
            if nxt in escapes:
                out.append(escapes[nxt])
                i += 2
                continue
            if 48 <= nxt <= 55:  # octal \ddd
                oct_digits = bytes([nxt])
                j = i + 2
                while j < min(i + 4, n) and 48 <= raw[j] <= 55:
                    oct_digits += bytes([raw[j]])
                    j += 1
                out.append(int(oct_digits, 8) & 0xFF)
                i = j
                continue
            if nxt in (10, 13):  # line continuation
                i += 3 if (nxt == 13 and i + 2 < n and raw[i + 2] == 10) else 2
                continue
            out.append(nxt)
            i += 2
        else:
            out.append(ch)
            i += 1
    if out.startswith(b"\xfe\xff"):
        return out[2:].decode("utf-16-be", errors="replace")
    try:
        return out.decode("utf-8")
    except UnicodeDecodeError:
        return out.decode("latin-1", errors="replace")


def _extract_pdf_text_stdlib(pdf_path: Path) -> List[str]:
    """Fallback stdlib PDF text extractor for uncompressed/FlateDecode content streams."""
    data = pdf_path.read_bytes()
    streams = re.findall(rb"stream\r?\n(.*?)\r?\n?endstream", data, re.DOTALL)
    extracted_pages: List[str] = []

    for raw_stream in streams:
        decoded_stream = raw_stream
        try:
            decoded_stream = zlib.decompress(raw_stream.strip(b"\r\n"))
        except zlib.error:
            pass
        if b"BT" not in decoded_stream or (b"Tj" not in decoded_stream and b"TJ" not in decoded_stream):
            continue

        page_lines: List[str] = []
        for bt_block in re.findall(rb"BT(.*?)ET", decoded_stream, re.DOTALL):
            # Extract lines split across Td/TD/T* or separate Tj/TJ instructions
            tokens: List[str] = []
            i = 0
            bn = len(bt_block)
            while i < bn:
                bch = bt_block[i]
                if bch == 40:  # '('
                    depth = 1
                    j = i + 1
                    buf = bytearray()
                    while j < bn and depth > 0:
                        c = bt_block[j]
                        if c == 92 and j + 1 < bn:
                            buf.append(c)
                            buf.append(bt_block[j + 1])
                            j += 2
                            continue
                        if c == 40:
                            depth += 1
                        elif c == 41:
                            depth -= 1
                            if depth == 0:
                                j += 1
                                break
                        buf.append(c)
                        j += 1
                    tokens.append(_decode_pdf_literal(bytes(buf)))
                    i = j
                    continue
                if bch == 60 and i + 1 < bn and bt_block[i + 1] != 60:  # '<hex>'
                    end_hex = bt_block.find(b">", i + 1)
                    if end_hex != -1:
                        hex_s = re.sub(rb"\s+", b"", bt_block[i + 1 : end_hex]).decode("ascii", errors="ignore")
                        if len(hex_s) % 2 == 1:
                            hex_s += "0"
                        try:
                            raw_bytes = bytes.fromhex(hex_s)
                            tokens.append(
                                raw_bytes[2:].decode("utf-16-be", errors="replace")
                                if raw_bytes.startswith(b"\xfe\xff")
                                else raw_bytes.decode("latin-1", errors="replace")
                            )
                        except ValueError:
                            pass
                        i = end_hex + 1
                        continue
                # Newline text positioning operators mark visual line breaks
                if bt_block[i : i + 2] in (b"Td", b"TD", b"T*", b"Tm"):
                    if tokens:
                        line_str = "".join(tokens).strip()
                        if line_str:
                            page_lines.append(line_str)
                        tokens.clear()
                    i += 2
                    continue
                i += 1
            if tokens:
                line_str = "".join(tokens).strip()
                if line_str:
                    page_lines.append(line_str)
        if page_lines:
            extracted_pages.append("\n".join(page_lines))
    return extracted_pages


def _extract_pdf_pages_and_toc(pdf_path: Path) -> Tuple[List[str], List[Tuple[str, int]]]:
    """Extract (pages_text, toc_entries) from a PDF using best available engine."""
    toc_entries: List[Tuple[str, int]] = []
    pages: List[str] = []

    # Engine 1: PyMuPDF (fitz)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            try:
                import pymupdf as fitz_mod  # type: ignore
            except ImportError:
                import fitz as fitz_mod  # type: ignore
        with fitz_mod.open(str(pdf_path)) as doc:
            try:
                for lvl, title, page_num in doc.get_toc():
                    if lvl <= 2 and title.strip() and page_num >= 1:
                        toc_entries.append((title.strip(), int(page_num) - 1))
            except Exception:
                toc_entries = []
            pages = [page.get_text("text") or "" for page in doc]
            if any(p.strip() for p in pages):
                return pages, toc_entries
    except ImportError:
        pass
    except Exception:
        pages = []

    # Engine 2: pdfplumber
    try:
        import pdfplumber  # type: ignore
        with pdfplumber.open(str(pdf_path)) as pdf:
            pages = [(p.extract_text() or "") for p in pdf.pages]
        if any(p.strip() for p in pages):
            return pages, toc_entries
    except ImportError:
        pass
    except Exception:
        pages = []

    # Engine 3: pdfminer.high_level
    try:
        from pdfminer.high_level import extract_text as pdfminer_extract  # type: ignore
        raw = pdfminer_extract(str(pdf_path)) or ""
        if raw.strip():
            return [p for p in raw.split("\x0c") if p.strip()], toc_entries
    except ImportError:
        pass
    except Exception:
        pass

    # Engine 4: pypdf / PyPDF2
    for mod_name in ("pypdf", "PyPDF2"):
        try:
            mod = __import__(mod_name)
            reader = mod.PdfReader(str(pdf_path))
            pages = [(page.extract_text() or "") for page in reader.pages]
            if any(p.strip() for p in pages):
                return pages, toc_entries
        except ImportError:
            continue
        except Exception:
            pages = []

    # Engine 5: CLI fallbacks (pdftotext / mutool)
    if shutil.which("pdftotext"):
        try:
            res = subprocess.run(
                ["pdftotext", "-layout", str(pdf_path), "-"],
                capture_output=True, text=True, check=True,
            )
            if res.stdout.strip():
                return [p for p in res.stdout.split("\x0c") if p.strip()], toc_entries
        except subprocess.SubprocessError:
            pass
    if shutil.which("mutool"):
        try:
            res = subprocess.run(
                ["mutool", "draw", "-F", "txt", "-o", "-", str(pdf_path)],
                capture_output=True, text=True, check=True,
            )
            if res.stdout.strip():
                return [res.stdout], toc_entries
        except subprocess.SubprocessError:
            pass

    # Engine 6: Pure stdlib stream extractor
    pages = _extract_pdf_text_stdlib(pdf_path)
    return pages, toc_entries


def _attach_footnotes_to_units(
    units: List[Tuple[str, str, str]],
    page_bodies: Sequence[str],
    footnotes_per_page: Sequence[List[str]],
) -> List[Tuple[str, str, str]]:
    """Append detached PDF page footnotes cleanly to the end of their owning section unit."""
    if not any(footnotes_per_page) or not units:
        return units
    if len(units) == 1:
        all_fn = [fn for page_fns in footnotes_per_page for fn in page_fns]
        loc, title, body = units[0]
        return [(loc, title, f"{body.rstrip()}\n\n" + "\n\n".join(all_fn))]

    start_pages: List[int] = []
    cursor = 0
    for _loc, title, _body in units:
        clean_title = re.sub(r"^#+\s*", "", title).strip().lower()
        found_p = cursor
        if clean_title:
            for p_idx in range(cursor, len(page_bodies)):
                if clean_title in page_bodies[p_idx].lower():
                    found_p = p_idx
                    cursor = p_idx
                    break
        start_pages.append(found_p)

    out: List[Tuple[str, str, str]] = []
    for idx, (loc, title, body) in enumerate(units):
        p_begin = start_pages[idx]
        p_end = start_pages[idx + 1] if idx + 1 < len(start_pages) else len(footnotes_per_page)
        sec_fns = [fn for p_i in range(p_begin, max(p_begin + 1, p_end)) for fn in footnotes_per_page[p_i]]
        if sec_fns:
            body = f"{body.rstrip()}\n\n" + "\n\n".join(sec_fns)
        out.append((loc, title, body))
    return out


def _join_pdf_pages_for_reflow(page_bodies: Sequence[str]) -> str:
    """Join PDF page bodies without introducing false paragraph breaks mid-sentence."""
    non_empty = [p.strip() for p in page_bodies if p.strip()]
    if not non_empty:
        return ""
    parts: List[str] = [non_empty[0]]
    term_punct = (".", "!", "?", "…", '"', "”", "」", "。", "！", "？", ":")
    for nxt in non_empty[1:]:
        prev_lines = [ln.strip() for ln in parts[-1].splitlines() if ln.strip()]
        nxt_lines = [ln.strip() for ln in nxt.splitlines() if ln.strip()]
        prev_last = prev_lines[-1] if prev_lines else ""
        nxt_first = nxt_lines[0] if nxt_lines else ""
        nxt_is_break = bool(
            _CHAPTER_LINE_RE.match(nxt_first)
            or re.match(r"^(?:#{1,6}\s+|[-*•–—]\s+|\d+[.)]\s+|>\s+)", nxt_first)
        )
        sep = "\n" if (prev_last and not prev_last.endswith(term_punct) and not nxt_is_break) else "\n\n"
        parts.append(sep + nxt)
    return "".join(parts)


def _extract_pdf_units(pdf_path: Path) -> List[Tuple[str, str, str]]:
    """Extract structured (source_location, title, normalized_markdown_text) units from a PDF."""
    pages, toc_entries = _extract_pdf_pages_and_toc(pdf_path)
    cleaned_pages = _strip_pdf_running_chrome(pages)
    page_bodies, footnotes_per_page = _extract_pdf_page_footnotes(cleaned_pages)
    combined = _join_pdf_pages_for_reflow(page_bodies)
    if not combined.strip():
        raise ValueError(
            f"No extractable text found in PDF '{pdf_path.name}' "
            "(it may be an image-only scan requiring OCR first)."
        )

    reflowed = _reflow_pdf_text(combined)
    sections = _split_markdown_sections(reflowed, pdf_path.name)
    if len(sections) >= 2:
        return _attach_footnotes_to_units(sections, page_bodies, footnotes_per_page)

    # If heading heuristic found <= 1 section but PDF TOC bookmarks exist, split by TOC page ranges
    valid_toc: List[Tuple[str, int]] = []
    seen_pages: set = set()
    for title, pidx in toc_entries:
        if 0 <= pidx < len(page_bodies) and pidx not in seen_pages:
            seen_pages.add(pidx)
            valid_toc.append((title, pidx))
    valid_toc.sort(key=lambda item: item[1])

    if len(valid_toc) >= 2:
        toc_units: List[Tuple[str, str, str]] = []
        first_pidx = valid_toc[0][1]
        if first_pidx > 0:
            front = _reflow_pdf_text(_join_pdf_pages_for_reflow(page_bodies[:first_pidx]))
            front_fns = [fn for p_i in range(0, first_pidx) for fn in footnotes_per_page[p_i]]
            if front_fns and front.strip():
                front = f"{front.rstrip()}\n\n" + "\n\n".join(front_fns)
            if front.strip():
                toc_units.append((f"{pdf_path.name}#pp.1-{first_pidx}", "Front Matter", f"# Front Matter\n\n{front}"))
        for idx, (title, start_p) in enumerate(valid_toc):
            end_p = valid_toc[idx + 1][1] if idx + 1 < len(valid_toc) else len(page_bodies)
            body = _reflow_pdf_text(_join_pdf_pages_for_reflow(page_bodies[start_p:end_p]))
            sec_fns = [fn for p_i in range(start_p, end_p) for fn in footnotes_per_page[p_i]]
            if sec_fns and body.strip():
                body = f"{body.rstrip()}\n\n" + "\n\n".join(sec_fns)
            if body.strip():
                body_out = body if body.lstrip().startswith("#") else f"# {title}\n\n{body}"
                toc_units.append((f"{pdf_path.name}#pp.{start_p + 1}-{end_p}", title, body_out))
        if toc_units:
            return toc_units

    # Last fallback: group pages into balanced sections (~2500 words or 10 pages max per unit)
    if len(page_bodies) > 10 and count_words(reflowed) > 2500:
        page_units: List[Tuple[str, str, str]] = []
        buf: List[str] = []
        buf_fns: List[str] = []
        start_p = 1
        for pno, ptext in enumerate(page_bodies, 1):
            if ptext.strip():
                buf.append(_reflow_pdf_text(ptext))
            buf_fns.extend(footnotes_per_page[pno - 1])
            if buf and (count_words("\n\n".join(buf)) >= 2000 or (pno - start_p + 1) >= 10):
                title = f"Pages {start_p}-{pno}"
                body_str = f"# {title}\n\n" + "\n\n".join(buf)
                if buf_fns:
                    body_str += "\n\n" + "\n\n".join(buf_fns)
                page_units.append((f"{pdf_path.name}#pp.{start_p}-{pno}", title, body_str))
                buf = []
                buf_fns = []
                start_p = pno + 1
        if buf:
            title = f"Pages {start_p}-{len(page_bodies)}"
            body_str = f"# {title}\n\n" + "\n\n".join(buf)
            if buf_fns:
                body_str += "\n\n" + "\n\n".join(buf_fns)
            page_units.append((f"{pdf_path.name}#pp.{start_p}-{len(page_bodies)}", title, body_str))
        if page_units:
            return page_units

    return _attach_footnotes_to_units([(pdf_path.name, pdf_path.stem, reflowed)], page_bodies, footnotes_per_page)


def _strip_inline_markdown(text: str) -> str:
    """Strip inline Markdown markers while preserving normal text and punctuation."""
    s = re.sub(r"!\[([^\]]*)\]\([^)]+\)", r"\1", text)
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    s = re.sub(r"\^\{([^}]+)\}", r"[\1]", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)
    s = re.sub(r"__([^_]+)__", r"\1", s)
    s = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"\1", s)
    s = re.sub(r"(?<!\w)_([^_\n]+)_(?!\w)", r"\1", s)
    return s


def _markdown_to_plain_txt(md_text: str) -> str:
    """Convert Markdown text into clean publication-ready plain text."""
    out_lines: List[str] = []
    in_fence = False
    for line in _strip_block_anchors(md_text).splitlines():
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            out_lines.append(line.rstrip())
            continue
        m_head = re.match(r"^(#{1,6})\s+(.+)$", s)
        if m_head:
            level = len(m_head.group(1))
            title = _strip_inline_markdown(m_head.group(2).strip())
            if level == 1:
                out_lines.append(title)
                out_lines.append("=" * min(max(len(title), 4), 60))
            elif level == 2:
                out_lines.append(title)
                out_lines.append("-" * min(max(len(title), 4), 50))
            else:
                out_lines.append(title)
            continue
        if s.startswith(">"):
            out_lines.append(_strip_inline_markdown(s.lstrip(">").strip()))
            continue
        out_lines.append(_strip_inline_markdown(line.rstrip()))

    rendered = "\n".join(out_lines)
    rendered = re.sub(r"\n{3,}", "\n\n", rendered)
    return rendered.strip()


def render_plain_txt(
    units: Sequence[Tuple[str, str]],
    toc_lines: Optional[Sequence[str]] = None,
    title: Optional[str] = None,
) -> str:
    """Render (chapter_title, markdown_or_text) pairs into clean plain UTF-8 text."""
    parts: List[str] = []
    if title:
        clean_title = _strip_inline_markdown(title.strip())
        parts.append(f"{clean_title}\n{'=' * min(max(len(clean_title), 8), 64)}")
    if toc_lines:
        clean_toc = [
            re.sub(r"^(\s*)-\s+", r"\1* ", _strip_inline_markdown(ln))
            for ln in toc_lines
        ]
        parts.append("TABLE OF CONTENTS\n-----------------\n" + "\n".join(clean_toc))
    for _ch_title, body in units:
        plain = _markdown_to_plain_txt(body)
        if plain:
            parts.append(plain)
    return "\n\n".join(parts).rstrip() + "\n"


def _extract_orig_inline_assets(orig_inner: str) -> Tuple[Dict[str, List[Tuple[str, bool, str]]], Dict[str, str], str]:
    """Index original <a>, <img>, and <sup> inline markup from XHTML leaf block content."""
    links_by_href: Dict[str, List[Tuple[str, bool, str]]] = {}
    imgs_by_src: Dict[str, str] = {}
    sup_open_default = "<sup>"

    for m_a in re.finditer(r"(?is)(<a\b([^>]*)>)(.*?)</a>", orig_inner):
        open_tag, attrs, body = m_a.group(1), m_a.group(2), m_a.group(3)
        m_href = re.search(r'\bhref\s*=\s*(["\'])(.*?)\1', attrs, re.IGNORECASE)
        if not m_href:
            continue
        href_key = html.unescape(m_href.group(2)).strip()
        m_sup = re.match(r"^\s*(<sup\b[^>]*>)(.*?)</sup>\s*$", body, re.IGNORECASE | re.DOTALL)
        had_sup = bool(m_sup)
        sup_open = m_sup.group(1) if m_sup else "<sup>"
        links_by_href.setdefault(href_key, []).append((open_tag, had_sup, sup_open))

    for m_img in re.finditer(r"(?is)<img\b([^>]*)/?>", orig_inner):
        m_src = re.search(r'\bsrc\s*=\s*(["\'])(.*?)\1', m_img.group(1), re.IGNORECASE)
        if m_src:
            src_key = html.unescape(m_src.group(2)).strip()
            tag_txt = m_img.group(0)
            if not tag_txt.endswith("/>"):
                tag_txt = tag_txt[:-1] + "/>"
            imgs_by_src.setdefault(src_key, tag_txt)

    m_plain_sup = re.search(r"(?is)<sup\b[^>]*>", orig_inner)
    if m_plain_sup:
        sup_open_default = m_plain_sup.group(0)

    return links_by_href, imgs_by_src, sup_open_default


def _inline_md_to_xhtml(text: str, orig_inner: str = "") -> str:
    """Escape HTML and render Markdown inline spans while preserving original <a>/<sup>/<img> attrs."""
    links_by_href, imgs_by_src, sup_open_default = (
        _extract_orig_inline_assets(orig_inner) if orig_inner else ({}, {}, "<sup>")
    )
    tokens: List[str] = []

    def _stash(rendered_html: str) -> str:
        tok = f"\x00MDTOK{len(tokens)}\x00"
        tokens.append(rendered_html)
        return tok

    def _render_simple_inline(segment: str) -> str:
        esc = html.escape(segment, quote=False)
        esc = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", esc)
        esc = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"<em>\1</em>", esc)
        return esc

    working = text
    working = re.sub(
        r"`([^`]+)`",
        lambda m: _stash(f"<code>{html.escape(m.group(1), quote=False)}</code>"),
        working,
    )

    def _stash_img(m: re.Match) -> str:
        alt, src = m.group(1).strip(), m.group(2).strip()
        is_img_ext = bool(re.search(r"\.(?:png|jpe?g|gif|svg|webp|bmp|avif)(?:[?#].*)?$", src, re.IGNORECASE))
        if src not in imgs_by_src and not is_img_ext:
            # Exclamation mark immediately preceding a footnote or cross-reference link
            return "!" + m.group(0)[1:]
        if src in imgs_by_src:
            return _stash(imgs_by_src[src])
        return _stash(
            f'<img src="{html.escape(src, quote=True)}" alt="{html.escape(alt, quote=True)}"/>'
        )

    working = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)", _stash_img, working)

    def _stash_link(m: re.Match) -> str:
        label, href = m.group(1), m.group(2).strip()
        rendered_lbl = _render_simple_inline(label)
        bucket = links_by_href.get(href)
        if bucket:
            open_a, had_sup, sup_open = bucket.pop(0)
            if had_sup:
                return _stash(f"{open_a}{sup_open}{rendered_lbl}</sup></a>")
            return _stash(f"{open_a}{rendered_lbl}</a>")
        return _stash(f'<a href="{html.escape(href, quote=True)}">{rendered_lbl}</a>')

    working = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", _stash_link, working)
    working = re.sub(
        r"\^\{([^}]+)\}",
        lambda m: _stash(f"{sup_open_default}{_render_simple_inline(m.group(1))}</sup>"),
        working,
    )

    escaped = html.escape(working, quote=False)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    escaped = re.sub(r"(?<!\w)\*([^*\n]+)\*(?!\w)", r"<em>\1</em>", escaped)
    for idx, tok_html in enumerate(tokens):
        escaped = escaped.replace(f"\x00MDTOK{idx}\x00", tok_html)
    return escaped


def _markdown_to_xhtml_body(md_text: str) -> str:
    """Convert Markdown text into valid XHTML body fragment."""
    md_text = _strip_block_anchors(md_text)
    html_parts: List[str] = []
    in_fence = False
    code_buf: List[str] = []
    in_ul = False
    in_ol = False
    para_buf: List[str] = []

    def _close_lists() -> None:
        nonlocal in_ul, in_ol
        if in_ul:
            html_parts.append("</ul>")
            in_ul = False
        if in_ol:
            html_parts.append("</ol>")
            in_ol = False

    def _flush_para() -> None:
        if para_buf:
            joined = " ".join(para_buf)
            html_parts.append(f"<p>{_inline_md_to_xhtml(joined)}</p>")
            para_buf.clear()

    for line in md_text.splitlines():
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            _flush_para()
            _close_lists()
            if in_fence:
                html_parts.append("<pre><code>" + html.escape("\n".join(code_buf)) + "</code></pre>")
                code_buf.clear()
                in_fence = False
            else:
                in_fence = True
            continue
        if in_fence:
            code_buf.append(line.rstrip())
            continue
        if not s:
            _flush_para()
            _close_lists()
            continue
        if re.match(r"^(?:-{3,}|\*{3,}|_{3,})$", s):
            _flush_para()
            _close_lists()
            html_parts.append("<hr />")
            continue
        m_head = re.match(r"^(#{1,6})\s+(.+)$", s)
        if m_head:
            _flush_para()
            _close_lists()
            lvl = min(6, len(m_head.group(1)))
            html_parts.append(f"<h{lvl}>{_inline_md_to_xhtml(m_head.group(2).strip())}</h{lvl}>")
            continue
        m_ul = re.match(r"^[-*•]\s+(.+)$", s)
        if m_ul:
            _flush_para()
            if in_ol:
                html_parts.append("</ol>")
                in_ol = False
            if not in_ul:
                html_parts.append("<ul>")
                in_ul = True
            html_parts.append(f"  <li>{_inline_md_to_xhtml(m_ul.group(1).strip())}</li>")
            continue
        m_ol = re.match(r"^\d+[.)]\s+(.+)$", s)
        if m_ol:
            _flush_para()
            if in_ul:
                html_parts.append("</ul>")
                in_ul = False
            if not in_ol:
                html_parts.append("<ol>")
                in_ol = True
            html_parts.append(f"  <li>{_inline_md_to_xhtml(m_ol.group(1).strip())}</li>")
            continue
        if s.startswith(">"):
            _flush_para()
            _close_lists()
            html_parts.append(f"<blockquote><p>{_inline_md_to_xhtml(s.lstrip('>').strip())}</p></blockquote>")
            continue
        _close_lists()
        para_buf.append(s)

    _flush_para()
    _close_lists()
    if in_fence and code_buf:
        html_parts.append("<pre><code>" + html.escape("\n".join(code_buf)) + "</code></pre>")
    return "\n".join(html_parts)


def write_epub_book(
    out_path: Path,
    chapters: Sequence[Tuple[str, str]],
    title: str = "Book",
    author: str = "d-transcreate",
    lang: str = "en",
) -> None:
    """Write a standards-compliant EPUB 2/3 archive from (chapter_title, markdown_text) pairs."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    book_uid = f"urn:uuid:{uuid.uuid4()}"
    safe_title = html.escape(title.strip() or "Book")
    safe_author = html.escape(author.strip() or "d-transcreate")
    safe_lang = html.escape(lang.strip() or "en")

    css_text = (
        "body { font-family: serif; line-height: 1.6; margin: 1.5em; }\n"
        "h1, h2, h3 { font-family: sans-serif; line-height: 1.25; }\n"
        "p { margin: 0 0 0.85em 0; }\n"
        "blockquote { margin: 1em 1.5em; font-style: italic; }\n"
    )

    manifest_items = [
        '    <item id="style" href="style.css" media-type="text/css"/>',
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
    ]
    spine_items: List[str] = []
    nav_links: List[str] = []
    ncx_points: List[str] = []
    chapter_files: List[Tuple[str, str]] = []

    for idx, (ch_title, ch_body) in enumerate(chapters, 1):
        fname = f"ch{idx:03d}.xhtml"
        item_id = f"ch{idx:03d}"
        clean_t = _strip_inline_markdown(ch_title.strip()) or f"Chapter {idx}"
        esc_t = html.escape(clean_t)
        body_html = _markdown_to_xhtml_body(ch_body)
        if not re.search(r"<h[1-6]\b", body_html):
            body_html = f"<h1>{esc_t}</h1>\n{body_html}"
        xhtml = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<!DOCTYPE html>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="' + safe_lang + '">\n'
            "<head>\n"
            f"  <title>{esc_t}</title>\n"
            '  <link rel="stylesheet" type="text/css" href="style.css"/>\n'
            "</head>\n"
            "<body>\n"
            f"{body_html}\n"
            "</body>\n"
            "</html>\n"
        )
        chapter_files.append((f"OEBPS/{fname}", xhtml))
        manifest_items.append(f'    <item id="{item_id}" href="{fname}" media-type="application/xhtml+xml"/>')
        spine_items.append(f'    <itemref idref="{item_id}"/>')
        nav_links.append(f'      <li><a href="{fname}">{esc_t}</a></li>')
        ncx_points.append(
            f'    <navPoint id="navPoint-{idx}" playOrder="{idx}">\n'
            f"      <navLabel><text>{esc_t}</text></navLabel>\n"
            f'      <content src="{fname}"/>\n'
            "    </navPoint>"
        )

    nav_xhtml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<!DOCTYPE html>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">\n'
        f"<head><title>{safe_title}</title></head>\n"
        "<body>\n"
        '  <nav epub:type="toc" id="toc">\n'
        "    <h1>Table of Contents</h1>\n"
        "    <ol>\n"
        + "\n".join(nav_links)
        + "\n    </ol>\n"
        "  </nav>\n"
        "</body>\n"
        "</html>\n"
    )

    toc_ncx = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">\n'
        "  <head>\n"
        f'    <meta name="dtb:uid" content="{book_uid}"/>\n'
        '    <meta name="dtb:depth" content="1"/>\n'
        "  </head>\n"
        f"  <docTitle><text>{safe_title}</text></docTitle>\n"
        "  <navMap>\n"
        + "\n".join(ncx_points)
        + "\n  </navMap>\n"
        "</ncx>\n"
    )

    content_opf = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">\n'
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        f'    <dc:identifier id="bookid">{book_uid}</dc:identifier>\n'
        f"    <dc:title>{safe_title}</dc:title>\n"
        f"    <dc:creator>{safe_author}</dc:creator>\n"
        f"    <dc:language>{safe_lang}</dc:language>\n"
        f'    <meta property="dcterms:modified">{datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}</meta>\n'
        "  </metadata>\n"
        "  <manifest>\n"
        + "\n".join(manifest_items)
        + "\n  </manifest>\n"
        '  <spine toc="ncx">\n'
        + "\n".join(spine_items)
        + "\n  </spine>\n"
        "</package>\n"
    )

    container_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        "  <rootfiles>\n"
        '    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>\n'
        "  </rootfiles>\n"
        "</container>\n"
    )

    with zipfile.ZipFile(out_path, "w") as zf:
        zf.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        zf.writestr("META-INF/container.xml", container_xml, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/style.css", css_text, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/nav.xhtml", nav_xhtml, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/toc.ncx", toc_ncx, compress_type=zipfile.ZIP_DEFLATED)
        zf.writestr("OEBPS/content.opf", content_opf, compress_type=zipfile.ZIP_DEFLATED)
        for arc_name, content in chapter_files:
            zf.writestr(arc_name, content, compress_type=zipfile.ZIP_DEFLATED)


# ---------------------------------------------------------------------------
# Section & Paragraph-boundary Chunking
# ---------------------------------------------------------------------------

def _first_heading_or_fallback(text: str, fallback: str) -> str:
    for line in text.splitlines():
        m = re.match(r"^\s*#{1,6}\s+(.+)$", line)
        if m:
            return m.group(1).strip()
        if _CHAPTER_LINE_RE.match(line):
            return line.strip()
    return fallback


def _has_body_text(lines: List[str]) -> bool:
    """Return True if lines contain at least one non-empty line that is not a Markdown ATX heading."""
    for ln in lines:
        s = ln.strip()
        if s and not re.match(r"^#{1,6}\s+\S", ln):
            return True
    return False


def _split_markdown_sections(text: str, source_label: str) -> List[Tuple[str, str, str]]:
    """Split Markdown on top-level # or ## headings outside fenced code blocks."""
    lines = text.splitlines()
    sections: List[Tuple[str, str, str]] = []
    current_lines: List[str] = []
    current_title = Path(source_label).stem
    in_fence = False
    has_headings = False

    for line in lines:
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            current_lines.append(line)
            continue
        if not in_fence and re.match(r"^#{1,2}\s+\S", line):
            has_headings = True
            body = "\n".join(current_lines).strip()
            if body and _has_body_text(current_lines):
                sections.append((source_label, current_title, body))
                current_lines = [line]
            else:
                current_lines.append(line)
            current_title = re.sub(r"^#{1,2}\s+", "", line).strip()
        else:
            current_lines.append(line)

    tail = "\n".join(current_lines).strip()
    if tail:
        sections.append((source_label, current_title, tail))
    if not has_headings and not sections and text.strip():
        sections.append((source_label, Path(source_label).stem, text.strip()))
    return sections


def _split_txt_chapters(text: str, source_label: str) -> List[Tuple[str, str, str]]:
    """Split plain text on Chapter/Chuong heading lines."""
    lines = text.splitlines()
    sections: List[Tuple[str, str, str]] = []
    current_lines: List[str] = []
    current_title = Path(source_label).stem

    for line in lines:
        if _CHAPTER_LINE_RE.match(line):
            body = "\n".join(current_lines).strip()
            if body:
                sections.append((source_label, current_title, body))
            current_title = line.strip()
            current_lines = [line]
        else:
            current_lines.append(line)

    tail = "\n".join(current_lines).strip()
    if tail:
        sections.append((source_label, current_title, tail))
    return sections


def _split_paragraphs_preserving_fences(text: str) -> List[str]:
    """Split text on blank lines while keeping fenced code blocks together."""
    paragraphs: List[str] = []
    current: List[str] = []
    in_fence = False

    for line in text.splitlines():
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            current.append(line)
            continue
        if not in_fence and s == "":
            if current:
                block = "\n".join(current).strip()
                if block:
                    paragraphs.append(block)
                current = []
        else:
            current.append(line)

    if current:
        block = "\n".join(current).strip()
        if block:
            paragraphs.append(block)
    return paragraphs


def split_unit_by_max_words(text: str, max_words: int) -> List[str]:
    """Split text at paragraph boundaries without ever splitting mid-paragraph."""
    if count_words(text) <= max_words:
        return [text.strip()]

    paragraphs = _split_paragraphs_preserving_fences(text)
    if not paragraphs:
        return [text.strip()]

    chunks: List[str] = []
    buf: List[str] = []
    buf_words = 0

    for para in paragraphs:
        pw = count_words(para)
        if buf and buf_words + pw > max_words:
            chunks.append("\n\n".join(buf).strip())
            buf = [para]
            buf_words = pw
        else:
            buf.append(para)
            buf_words += pw

    if buf:
        chunks.append("\n\n".join(buf).strip())
    return chunks


# ---------------------------------------------------------------------------
# CSV / JSONL Helpers
# ---------------------------------------------------------------------------

def read_csv_rows(path: Path, expected_header: List[str]) -> List[Dict[str, str]]:
    """Read a UTF-8 CSV file into a list of dicts aligned to expected_header."""
    if not path.is_file():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames is None:
            return []
        rows: List[Dict[str, str]] = []
        for raw in reader:
            row = {col: (raw.get(col) or "").strip() for col in expected_header}
            if any(row.values()):
                rows.append(row)
        return rows


def write_csv_rows(path: Path, header: List[str], rows: List[Dict[str, str]]) -> None:
    """Write rows to a UTF-8 (no BOM) RFC 4180 CSV file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header, lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({col: row.get(col, "") for col in header})


def glossary_key(row: Dict[str, str]) -> Tuple[str, str]:
    """Canonical deduplication key for glossary rows."""
    return (row.get("term", "").strip().lower(), row.get("context", "").strip().lower())


def resolve_memory_path(
    pack_root: Path,
    workspace: Optional[Path],
    memory_arg: Optional[str],
    target_lang_arg: Optional[str],
) -> Optional[Path]:
    """Resolve Tier-1 memory CSV path from explicit flag, target-lang, or brief."""
    if memory_arg:
        return Path(memory_arg).expanduser().resolve()

    lang_val = target_lang_arg
    if not lang_val and workspace:
        brief = workspace / "translation-brief.md"
        if brief.is_file():
            for line in brief.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*-\s*Target language:\s*(.+)$", line, re.IGNORECASE)
                if m and m.group(1).strip():
                    lang_val = m.group(1).strip()
                    break
    if not lang_val:
        return None

    prefix, _ = resolve_lang_info(lang_val)
    if not prefix:
        return None
    return pack_root / "memory" / f"glossary-{prefix}.csv"


_COMMON_DOMAIN_TERMS = {
    "prologue", "epilogue", "preface", "foreword", "afterword",
    "footnote", "appendix", "table of contents", "acknowledgement",
    "glossary", "pseudonym", "narrator",
}


def _row_matches_domain(row: Dict[str, str], domain: str) -> bool:
    """Determine whether a Tier-1 memory row matches the requested project domain."""
    dom = (domain or "all").strip().lower()
    if dom in ("", "all"):
        return True

    term_low = row.get("term", "").strip().lower()
    if term_low in _COMMON_DOMAIN_TERMS:
        return True

    tclass = row.get("term_class", "").strip().lower()
    meta_txt = " ".join([
        row.get("context", ""),
        row.get("notes", ""),
        row.get("evidence", ""),
    ]).lower()
    is_fantasy_lore = any(
        kw in meta_txt for kw in ("fantasy", "lore", "wuxia", "xianxia", "magic", "story_bible", "fiction")
    )

    if dom == "technical":
        return tclass != "legal-term" and not is_fantasy_lore
    if dom == "legal":
        return tclass != "technical-term" and not is_fantasy_lore
    if dom == "fiction":
        return tclass not in {"technical-term", "legal-term"}
    if dom == "general":
        return not is_fantasy_lore and tclass not in {"technical-term", "legal-term"}
    return True


def _collect_source_corpus(workspace: Path) -> str:
    """Return combined source text from source_chunks/ with @bN anchors stripped."""
    chunks_dir = workspace / "source_chunks"
    if not chunks_dir.is_dir():
        return ""
    parts = [
        _strip_block_anchors(p.read_text(encoding="utf-8", errors="replace"))
        for p in sorted(chunks_dir.glob("*.md"), key=lambda fp: natural_sort_key(fp.name))
    ]
    return "\n\n".join(parts)


_PROJECT_ONLY_TERM_CLASSES = {
    "proper-name", "proper_name", "proper-noun", "character", "place",
    "person", "organization", "work-specific", "location", "magic_skill", "rank_title",
}


def _is_project_specific_glossary_row(row: Dict[str, str]) -> bool:
    """Return True if a row represents a story/project-specific entity unsuitable for global memory."""
    tclass = row.get("term_class", "").strip().lower()
    if tclass in _PROJECT_ONLY_TERM_CLASSES:
        return True
    notes = row.get("notes", "").lower()
    return any(tag in notes for tag in ("[no-promote]", "project-only", "story-specific"))


def sync_evidence_ledgers(workspace: Path) -> Dict[str, int]:
    """
    Bidirectionally bridge Phase 3 evidence records between JSONL (evidence-ledger.jsonl)
    and d-research v3.3 37-column CSV (evidence-ledger.csv) by claim_id.
    """
    jsonl_path = workspace / "evidence-ledger.jsonl"
    csv_path = workspace / "evidence-ledger.csv"

    csv_rows = read_csv_rows(csv_path, D_RESEARCH_LEDGER_37_HEADER) if csv_path.is_file() else []
    csv_by_id: Dict[str, int] = {}
    for idx, r in enumerate(csv_rows):
        cid = r.get("claim_id", "").strip()
        if cid:
            csv_by_id[cid] = idx

    jsonl_records: List[Dict[str, Any]] = []
    jsonl_ids: Set[str] = set()
    if jsonl_path.is_file():
        for raw_line in jsonl_path.read_text(encoding="utf-8", errors="replace").splitlines():
            s = raw_line.strip()
            if not s:
                continue
            try:
                obj = json.loads(s)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                jsonl_records.append(obj)
                cid = str(obj.get("claim_id", "")).strip()
                if cid:
                    jsonl_ids.add(cid)

    added_to_csv = 0
    added_to_jsonl = 0
    next_seq = len(csv_rows) + 1

    for obj in jsonl_records:
        cid = str(obj.get("claim_id", "")).strip()
        if not cid:
            cid = f"C{next_seq:03d}"
            next_seq += 1
        if cid in csv_by_id:
            continue
        row = {col: str(obj.get(col, "")).strip() for col in D_RESEARCH_LEDGER_37_HEADER}
        row["claim_id"] = cid
        if not row["claim"]:
            row["claim"] = row["evidence"] or row["source_title"] or row["sub_question"]
        if not row["record_type"]:
            row["record_type"] = "claim"
        if not row["source_access_class"]:
            row["source_access_class"] = "standard_public"
        if not row["subject_class"]:
            row["subject_class"] = "unknown"
        if not row["purpose_category"]:
            row["purpose_category"] = "general_research"
        if not row["policy_tier"]:
            row["policy_tier"] = "R0"
        if not row["data_sensitivity"]:
            row["data_sensitivity"] = "public"
        if not row["discovery_disposition"]:
            row["discovery_disposition"] = "evidence"
        if not row["reporting_disposition"]:
            row["reporting_disposition"] = "main_findings"
        if not row["redaction_class"]:
            row["redaction_class"] = "none"
        csv_by_id[cid] = len(csv_rows)
        csv_rows.append(row)
        added_to_csv += 1

    for r in csv_rows:
        cid = r.get("claim_id", "").strip()
        if not cid or cid in jsonl_ids:
            continue
        jsonl_records.append({k: v for k, v in r.items() if v})
        jsonl_ids.add(cid)
        added_to_jsonl += 1

    if csv_rows or csv_path.is_file():
        write_csv_rows(csv_path, D_RESEARCH_LEDGER_37_HEADER, csv_rows)
    if added_to_jsonl > 0:
        jsonl_path.write_text(
            "\n".join(json.dumps(rec, ensure_ascii=False) for rec in jsonl_records) + "\n",
            encoding="utf-8",
        )

    return {
        "csv_rows": len(csv_rows),
        "jsonl_rows": len(jsonl_records),
        "added_to_csv": added_to_csv,
        "added_to_jsonl": added_to_jsonl,
    }


def sync_glossary_ops(
    pack_root: Path,
    workspace: Path,
    memory_arg: Optional[str] = None,
    seed: bool = False,
    promote: bool = False,
    target_lang: Optional[str] = None,
    domain: str = "all",
    filter_to_source: bool = False,
    approve_clean: bool = False,
    include_proper_nouns: bool = False,
) -> Dict[str, Any]:
    """Perform deterministic Tier-1/Tier-2 glossary seeding, inbox merge, ledger bridge, and guarded promotion."""
    glossary_path = workspace / "glossary.csv"
    inbox_path = workspace / "glossary-inbox.jsonl"
    memory_path = resolve_memory_path(pack_root, workspace, memory_arg, target_lang)

    if not glossary_path.is_file():
        write_csv_rows(glossary_path, GLOSSARY_HEADER, [])

    rows = read_csv_rows(glossary_path, GLOSSARY_HEADER)
    index: Dict[Tuple[str, str], int] = {glossary_key(r): i for i, r in enumerate(rows)}

    seeded_count = 0
    domain_skipped = 0
    pruned_unused = 0
    inbox_added = 0
    inbox_skipped_dup = 0
    auto_approved_count = 0
    promoted_count = 0
    promoted_skipped_project = 0
    conflicts: List[Dict[str, str]] = []
    warnings: List[str] = []

    if seed:
        if memory_path is None:
            warnings.append("Could not determine target language for memory seeding.")
        elif not memory_path.is_file():
            if memory_arg:
                raise FileNotFoundError(f"Memory glossary not found: {memory_path}")
            warnings.append(f"No memory glossary found at {memory_path}; skipped seeding.")
        else:
            mem_rows = read_csv_rows(memory_path, GLOSSARY_HEADER)
            for mr in mem_rows:
                if mr.get("status", "").lower() != "approved":
                    continue
                if not _row_matches_domain(mr, domain):
                    domain_skipped += 1
                    continue
                k = glossary_key(mr)
                if not k[0]:
                    continue
                if k in index:
                    continue
                index[k] = len(rows)
                rows.append(mr)
                seeded_count += 1

    if inbox_path.is_file():
        raw_lines = inbox_path.read_text(encoding="utf-8").splitlines()
        for line_no, raw_line in enumerate(raw_lines, 1):
            stripped = raw_line.strip()
            if not stripped:
                continue
            try:
                obj = json.loads(stripped)
            except json.JSONDecodeError as exc:
                raise ValueError(f"Invalid JSON in glossary-inbox.jsonl line {line_no}: {exc}") from exc
            if not isinstance(obj, dict):
                raise ValueError(f"glossary-inbox.jsonl line {line_no} must be a JSON object")

            term = str(obj.get("term", "")).strip()
            pref = str(obj.get("preferred_translation", "")).strip()
            if not term or not pref:
                raise ValueError(
                    f"glossary-inbox.jsonl line {line_no} missing required 'term' or 'preferred_translation'"
                )

            conf_val = (str(obj.get("confidence", "medium")).strip() or "medium").lower()
            stat_val = (str(obj.get("status", "proposed")).strip() or "proposed").lower()
            if approve_clean and stat_val == "proposed" and conf_val in {"high", "medium"}:
                stat_val = "approved"
                auto_approved_count += 1

            candidate = {
                "term": term,
                "preferred_translation": pref,
                "forbidden_translation": str(obj.get("forbidden_translation", "")).strip(),
                "term_class": str(obj.get("term_class", "concept")).strip() or "concept",
                "context": str(obj.get("context", "")).strip(),
                "source_location": str(obj.get("source_location", "")).strip() or "inbox",
                "evidence": str(obj.get("evidence", "worker-inbox")).strip() or "worker-inbox",
                "confidence": conf_val,
                "status": stat_val,
                "notes": str(obj.get("notes", "")).strip(),
            }
            k = glossary_key(candidate)
            if k in index:
                existing = rows[index[k]]
                if existing["preferred_translation"].strip() != pref:
                    conflicts.append({
                        "term": term,
                        "context": candidate["context"],
                        "existing_preferred": existing["preferred_translation"],
                        "incoming_preferred": pref,
                        "line": str(line_no),
                    })
                else:
                    inbox_skipped_dup += 1
            else:
                index[k] = len(rows)
                rows.append(candidate)
                inbox_added += 1

    if approve_clean:
        conflict_terms = {(c["term"].lower(), c["context"].lower()) for c in conflicts}
        for r in rows:
            if (
                r.get("status", "").lower() == "proposed"
                and r.get("confidence", "").lower() in {"high", "medium"}
                and glossary_key(r) not in conflict_terms
            ):
                r["status"] = "approved"
                auto_approved_count += 1

    if filter_to_source:
        corpus = _collect_source_corpus(workspace)
        if not corpus:
            warnings.append("No scanned source_chunks/ found; skipped --filter-to-source pruning.")
        else:
            filtered_rows: List[Dict[str, str]] = []
            for r in rows:
                is_mem_seed = r.get("source_location", "").strip().lower() == "memory-seed"
                term_val = r.get("term", "").strip()
                if is_mem_seed and term_val and not _phrase_pattern(term_val).search(corpus):
                    pruned_unused += 1
                    continue
                filtered_rows.append(r)
            rows = filtered_rows

    write_csv_rows(glossary_path, GLOSSARY_HEADER, rows)

    if promote:
        if memory_path is None:
            raise ValueError("Cannot --promote without target language or --memory path.")
        mem_rows = read_csv_rows(memory_path, GLOSSARY_HEADER) if memory_path.is_file() else []
        mem_index: Dict[Tuple[str, str], int] = {glossary_key(r): i for i, r in enumerate(mem_rows)}
        for r in rows:
            if r.get("status", "").lower() == "approved" and r.get("confidence", "").lower() == "high":
                if not include_proper_nouns and _is_project_specific_glossary_row(r):
                    promoted_skipped_project += 1
                    continue
                k = glossary_key(r)
                if not k[0]:
                    continue
                if k in mem_index:
                    existing_mem = mem_rows[mem_index[k]]
                    if existing_mem["preferred_translation"].strip() != r["preferred_translation"].strip():
                        conflicts.append({
                            "term": r["term"],
                            "context": r["context"],
                            "existing_preferred": existing_mem["preferred_translation"],
                            "incoming_preferred": r["preferred_translation"],
                            "scope": "promote",
                        })
                    continue
                mem_index[k] = len(mem_rows)
                mem_rows.append(r)
                promoted_count += 1
        write_csv_rows(memory_path, GLOSSARY_HEADER, mem_rows)

    ledger_sync = sync_evidence_ledgers(workspace)

    return {
        "glossary_path": str(glossary_path),
        "memory_path": str(memory_path) if memory_path else None,
        "total_project_rows": len(rows),
        "seeded": seeded_count,
        "domain_skipped": domain_skipped,
        "pruned_unused": pruned_unused,
        "inbox_added": inbox_added,
        "inbox_duplicates_skipped": inbox_skipped_dup,
        "auto_approved": auto_approved_count,
        "promoted": promoted_count,
        "promoted_skipped_project_specific": promoted_skipped_project,
        "ledger_sync": ledger_sync,
        "conflicts": conflicts,
        "warnings": warnings,
    }


# ---------------------------------------------------------------------------
# Subcommand: init
# ---------------------------------------------------------------------------

def _populate_brief_text(
    text: str,
    source: str,
    version: str,
    source_lang: str,
    target_lang: str,
    target_locale: str,
    audience: str,
    mode: str,
    output_format: Optional[str] = None,
) -> str:
    replacements = {
        "- Source files:": f"- Source files: {source}",
        "- Skill version:": f"- Skill version: {version}",
        "- Source language:": f"- Source language: {source_lang}",
        "- Target language:": f"- Target language: {target_lang}",
        "- Target locale:": f"- Target locale: {target_locale}",
        "- Audience:": f"- Audience: {audience}",
        "- Mode:": f"- Mode: {mode}",
    }
    if output_format:
        replacements["- Output format:"] = f"- Output format: {output_format}"
    out_lines: List[str] = []
    for line in text.splitlines():
        replaced = False
        for prefix, new_line in replacements.items():
            if line.strip().startswith(prefix):
                out_lines.append(new_line)
                replaced = True
                break
        if not replaced:
            out_lines.append(line)
    return "\n".join(out_lines) + "\n"


def _populate_dossier_text(text: str, source_lang: str, target_lang: str) -> str:
    out_lines: List[str] = []
    for line in text.splitlines():
        if line.strip().startswith("- source_language:"):
            out_lines.append(f"- source_language: {source_lang}")
        elif line.strip().startswith("- target_language:"):
            out_lines.append(f"- target_language: {target_lang}")
        else:
            out_lines.append(line)
    return "\n".join(out_lines) + "\n"


def cmd_init(args: argparse.Namespace, pack_root: Path) -> int:
    workspace = Path(args.workspace).expanduser().resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    for sub in ("output", "summaries", "proposals"):
        (workspace / sub).mkdir(parents=True, exist_ok=True)

    templates_dir = pack_root / "templates"
    copied_templates: List[str] = []
    for name in TEMPLATE_FILES:
        dest = workspace / name
        src = templates_dir / name
        if src.is_file():
            shutil.copyfile(src, dest)
        else:
            dest.write_text(FALLBACK_TEMPLATES[name], encoding="utf-8")
        copied_templates.append(name)

    for jsonl_name in ("glossary-inbox.jsonl", "evidence-ledger.jsonl"):
        p = workspace / jsonl_name
        if not p.exists():
            p.write_text("", encoding="utf-8")

    csv_ledger = workspace / "evidence-ledger.csv"
    if not csv_ledger.exists():
        write_csv_rows(csv_ledger, D_RESEARCH_LEDGER_37_HEADER, [])

    cov_path = workspace / "research-coverage.json"
    if not cov_path.exists():
        cov_path.write_text(
            json.dumps({"status": "initialized", "categories": {}, "sources_checked": []}, indent=2) + "\n",
            encoding="utf-8",
        )

    lang_prefix, default_locale = resolve_lang_info(args.target_lang)
    version = read_pack_version(pack_root)
    source_lang = args.source_lang or "auto-detect"
    mode = args.mode or "faithful translation with light transcreation for idioms and dialogue"
    audience = args.audience or "General readers"
    domain = getattr(args, "domain", "all") or "all"
    output_format = getattr(args, "output_format", None)
    if not output_format and str(args.source).lower().endswith(".pdf"):
        output_format = "txt, epub"

    brief_path = workspace / "translation-brief.md"
    brief_text = brief_path.read_text(encoding="utf-8")
    brief_path.write_text(
        _populate_brief_text(
            brief_text, args.source, version, source_lang, args.target_lang,
            default_locale, audience, mode, output_format=output_format,
        ),
        encoding="utf-8",
    )

    dossier_path = workspace / "research-dossier.md"
    if dossier_path.is_file():
        dossier_text = dossier_path.read_text(encoding="utf-8")
        dossier_path.write_text(_populate_dossier_text(dossier_text, source_lang, args.target_lang), encoding="utf-8")

    if lang_prefix == "vi":
        style_path = workspace / "style-sheet.md"
        style_text = style_path.read_text(encoding="utf-8")
        if "core/locales/vi-VN.md" not in style_text:
            style_text = style_text.rstrip() + (
                "\n\n- Locale profile reference: `core/locales/vi-VN.md` "
                "(Vietnamese pronoun matrix, Hán-Việt vs. native balance, anti-translatorese rules).\n"
            )
            style_path.write_text(style_text, encoding="utf-8")

    sync_res = sync_glossary_ops(
        pack_root=pack_root,
        workspace=workspace,
        seed=True,
        target_lang=args.target_lang,
        domain=domain,
    )

    result = {
        "command": "init",
        "workspace": str(workspace),
        "skill_version": version,
        "target_lang": args.target_lang,
        "lang_prefix": lang_prefix,
        "templates_initialized": len(copied_templates),
        "seeded_glossary_rows": sync_res["seeded"],
        "memory_path": sync_res["memory_path"],
        "warnings": sync_res["warnings"],
    }
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"Initialized workspace: {workspace}")
        print(f"  Skill version : {version}")
        print(f"  Target lang   : {args.target_lang} (locale {default_locale})")
        print(f"  Seeded terms  : {sync_res['seeded']} from {sync_res['memory_path']}")
        for w in sync_res["warnings"]:
            print(f"  WARN: {w}")
    return 0


# ---------------------------------------------------------------------------
# Subcommand: scan
# ---------------------------------------------------------------------------

def _write_converted_txt_and_epub(
    pdf_path: Path,
    pdf_units: Sequence[Tuple[str, str, str]],
    out_dir: Path,
    stem: Optional[str] = None,
) -> Dict[str, str]:
    """Write normalized .txt and .epub conversions for a scanned PDF into out_dir."""
    out_dir.mkdir(parents=True, exist_ok=True)
    safe_stem = slugify_id(stem or pdf_path.stem)
    txt_path = out_dir / f"{safe_stem}.txt"
    epub_path = out_dir / f"{safe_stem}.epub"

    chapter_pairs = [(title, body) for _loc, title, body in pdf_units]
    toc_lines = [f"- {title}" for title, _body in chapter_pairs] if len(chapter_pairs) > 1 else None
    txt_path.write_text(
        render_plain_txt(chapter_pairs, toc_lines=toc_lines, title=pdf_path.stem),
        encoding="utf-8",
    )
    write_epub_book(epub_path, chapter_pairs, title=pdf_path.stem, author="Source PDF", lang="und")
    return {
        "source_pdf": str(pdf_path),
        "converted_txt": str(txt_path),
        "converted_epub": str(epub_path),
    }


def _collect_source_units(
    source_path: Path,
    convert_dir: Optional[Path] = None,
) -> Tuple[List[Tuple[str, str, str]], List[Dict[str, str]]]:
    """Return (units, converted_sources) where each unit is (source_location, section_title, text)."""
    units: List[Tuple[str, str, str]] = []
    converted_sources: List[Dict[str, str]] = []

    def _from_single_file(fp: Path, label: str) -> List[Tuple[str, str, str]]:
        ext = fp.suffix.lower()
        if ext == ".epub":
            return _extract_epub_units(fp)
        if ext == ".pdf":
            pdf_units = _extract_pdf_units(fp)
            if convert_dir is not None:
                converted_sources.append(_write_converted_txt_and_epub(fp, pdf_units, convert_dir, stem=fp.stem))
            return pdf_units
        raw = fp.read_text(encoding="utf-8", errors="replace")
        if ext in {".html", ".htm", ".xhtml"}:
            extracted = extract_html_text(raw)
            return _split_markdown_sections(extracted, label)
        if ext in {".md", ".markdown"}:
            return _split_markdown_sections(raw, label)
        if ext == ".txt":
            return _split_txt_chapters(raw, label)
        return []

    if source_path.is_file():
        ext = source_path.suffix.lower()
        if ext not in SUPPORTED_TEXT_EXTS and ext not in {".epub", ".pdf"}:
            raise ValueError(f"Unsupported source file format: {source_path.name}")
        return _from_single_file(source_path, source_path.name), converted_sources

    if source_path.is_dir():
        files = [
            p
            for p in source_path.rglob("*")
            if p.is_file()
            and not any(part.startswith(".") for part in p.relative_to(source_path).parts)
            and (p.suffix.lower() in SUPPORTED_TEXT_EXTS or p.suffix.lower() in {".epub", ".pdf"})
        ]
        files.sort(key=lambda p: natural_sort_key(p.relative_to(source_path).as_posix()))
        for fp in files:
            rel_label = fp.relative_to(source_path).as_posix()
            ext = fp.suffix.lower()
            if ext == ".epub":
                units.extend(_extract_epub_units(fp))
            elif ext == ".pdf":
                pdf_units = _extract_pdf_units(fp)
                if convert_dir is not None:
                    converted_sources.append(
                        _write_converted_txt_and_epub(fp, pdf_units, convert_dir, stem=fp.stem)
                    )
                units.extend(pdf_units)
            else:
                raw = fp.read_text(encoding="utf-8", errors="replace")
                if ext in {".html", ".htm", ".xhtml"}:
                    extracted = extract_html_text(raw)
                else:
                    extracted = raw.strip()
                if not extracted:
                    continue
                title = _first_heading_or_fallback(extracted, fp.stem)
                units.append((rel_label, title, extracted))
        return units, converted_sources

    raise FileNotFoundError(f"Source path not found: {source_path}")


def cmd_scan(args: argparse.Namespace, pack_root: Path) -> int:
    source_path = Path(args.source).expanduser().resolve()
    workspace = Path(args.workspace).expanduser().resolve()
    max_words = args.max_words
    if max_words <= 0:
        print("Error: --max-words must be positive", file=sys.stderr)
        return 1
    if not source_path.exists():
        print(f"Error: source path does not exist: {source_path}", file=sys.stderr)
        return 1

    source_epub_template: Optional[str] = None
    scan_records: List[Dict[str, Any]] = []
    converted_sources: List[Dict[str, str]] = []

    if source_path.is_file() and source_path.suffix.lower() == ".epub":
        try:
            workspace.mkdir(parents=True, exist_ok=True)
            template_name = ".source-template.epub"
            shutil.copy2(source_path, workspace / template_name)
            source_epub_template = template_name
            scan_records = _extract_epub_scan_records(source_path, max_words)
        except Exception as exc:
            print(f"Error scanning EPUB source: {exc}", file=sys.stderr)
            return 1
    else:
        try:
            raw_units, converted_sources = _collect_source_units(
                source_path,
                convert_dir=workspace / "converted_source",
            )
        except Exception as exc:
            print(f"Error scanning source: {exc}", file=sys.stderr)
            return 1

        for unit_idx, (src_loc, title, unit_text) in enumerate(raw_units, 1):
            sub_texts = split_unit_by_max_words(unit_text, max_words)
            base_stem = Path(src_loc.split("#")[0]).stem if source_path.is_dir() else f"chunk-{unit_idx:03d}"
            for part_idx, chunk_text in enumerate(sub_texts, 1):
                candidate_stem = base_stem if len(sub_texts) == 1 else f"{base_stem}-p{part_idx:02d}"
                semantic_unit = title if len(sub_texts) == 1 else f"{title} (Part {part_idx}/{len(sub_texts)})"
                scan_records.append({
                    "source_location": src_loc,
                    "title": semantic_unit,
                    "text": chunk_text,
                    "candidate_stem": candidate_stem,
                    "epub_href": None,
                    "epub_block_start": None,
                    "epub_block_end": None,
                })

    if not scan_records:
        print(f"Error: no readable text units found in {source_path}", file=sys.stderr)
        return 1

    workspace.mkdir(parents=True, exist_ok=True)
    chunks_dir = workspace / "source_chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)
    (workspace / "output").mkdir(parents=True, exist_ok=True)

    used_ids: Dict[str, int] = {}
    manifest_rows: List[Dict[str, str]] = []
    meta_chunks: List[Dict[str, Any]] = []
    structure_rows: List[str] = []
    prev_chunk_id = ""
    total_words = 0

    for rec_idx, rec in enumerate(scan_records, 1):
        src_loc = str(rec["source_location"])
        semantic_unit = str(rec["title"])
        chunk_text = str(rec["text"])
        candidate_stem = str(rec.get("candidate_stem") or f"chunk-{rec_idx:03d}")
        candidate_id = slugify_id(candidate_stem)
        if candidate_id in used_ids:
            used_ids[candidate_id] += 1
            chunk_id = f"{candidate_id}-{used_ids[candidate_id]}"
        else:
            used_ids[candidate_id] = 1
            chunk_id = candidate_id

        chunk_rel_path = f"source_chunks/{chunk_id}.md"
        chunk_abs_path = workspace / chunk_rel_path
        chunk_abs_path.write_text(chunk_text.rstrip() + "\n", encoding="utf-8")

        words = count_words(chunk_text)
        chars = count_chars(chunk_text)
        paras = count_paragraphs(chunk_text)
        headings = count_headings(chunk_text)
        tables = count_tables(chunk_text)
        total_words += words

        output_rel = f"output/{chunk_id}.md"

        manifest_rows.append({
            "chunk_id": chunk_id,
            "source_location": src_loc,
            "word_or_page_range": f"{words} words",
            "semantic_unit": semantic_unit,
            "dependencies": prev_chunk_id,
            "assigned_to": "coordinator",
            "status": "ready",
            "output_path": output_rel,
            "qa_status": "pending",
            "notes": "",
        })

        meta_chunks.append({
            "chunk_id": chunk_id,
            "source_file": src_loc,
            "source_chunk_path": chunk_rel_path,
            "source_words": words,
            "source_chars": chars,
            "source_paragraphs": paras,
            "source_headings": headings,
            "source_tables": tables,
            "epub_href": rec.get("epub_href"),
            "epub_block_start": rec.get("epub_block_start"),
            "epub_block_end": rec.get("epub_block_end"),
        })

        safe_unit = semantic_unit.replace("|", "\\|")
        safe_loc = src_loc.replace("|", "\\|")
        structure_rows.append(
            f"| {chunk_id} | {safe_loc} | section ({words} words, {paras} paras) | {safe_unit} | standard |"
        )
        prev_chunk_id = chunk_id

    write_csv_rows(workspace / "chunk-manifest.csv", MANIFEST_HEADER, manifest_rows)

    converted_notes = ""
    if converted_sources:
        lines_conv = [
            f"- PDF converted: `{c['source_pdf']}` -> TXT `{c['converted_txt']}` & EPUB `{c['converted_epub']}`"
            for c in converted_sources
        ]
        converted_notes = "\n".join(lines_conv) + "\n"
    if source_epub_template:
        converted_notes += f"- Source EPUB template preserved: `{source_epub_template}` (layout/CSS/assets preserved on `.epub` merge)\n"

    meta_payload = {
        "version": read_pack_version(pack_root),
        "scanned_at": datetime.now(timezone.utc).isoformat(),
        "source": str(source_path),
        "source_epub_template": source_epub_template,
        "max_words": max_words,
        "total_chunks": len(meta_chunks),
        "total_words": total_words,
        "converted_sources": converted_sources,
        "chunks": meta_chunks,
    }
    (workspace / ".book-scan-meta.json").write_text(
        json.dumps(meta_payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # Auto-mine recurring candidate terms across all scanned chunks for Phase 3 research
    mined = mine_terms_ops(workspace, top_n=200, min_freq=2)
    cand_rows = []
    for cand in mined["candidates"][:25]:
        t_safe = cand["term"].replace("|", "\\|")
        status_mark = "in glossary" if cand["in_glossary"] else "needs research"
        cand_rows.append(
            f"| {t_safe} | {cand['category_guess']} | {cand['count']} | "
            f"{cand['chunk_count']} | {cand['first_chunk_id']} | {status_mark} |"
        )
    cand_section = (
        "\n\n## Recurring Entities & Candidate Terms\n"
        "| Term | Category | Count | Chunks | First Seen | Status |\n"
        "|---|---|---|---|---|---|\n"
        + ("\n".join(cand_rows) if cand_rows else "| (none detected at freq >= 2) | - | 0 | 0 | - | - |")
        + "\n"
    )

    source_map_content = (
        "# Source Map\n\n"
        "## Overview\n"
        f"- Source path: {source_path}\n"
        f"- Total chunks: {len(meta_chunks)}\n"
        f"- Total source words: {total_words}\n"
        f"{converted_notes}"
        "- Extraction hazards: None detected during automated scan\n\n"
        "## Structure\n"
        "| ID | Source location | Type | Notes | Risk |\n"
        "|---|---|---|---|---|\n"
        + "\n".join(structure_rows)
        + "\n\n## High-Risk Items\n"
        "| ID | Issue | Mitigation |\n"
        "|---|---|---|\n"
        + cand_section
    )
    (workspace / "source-map.md").write_text(source_map_content, encoding="utf-8")

    result = {
        "command": "scan",
        "workspace": str(workspace),
        "total_chunks": len(meta_chunks),
        "total_words": total_words,
        "layout_preserving_epub": bool(source_epub_template),
        "converted_sources": converted_sources,
        "candidate_terms_count": mined["total_candidates"],
        "candidate_terms_path": mined["output_path"],
        "chunk_ids": [c["chunk_id"] for c in meta_chunks],
    }
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"Scanned {source_path} -> {len(meta_chunks)} chunk(s), {total_words} word(s)")
        for conv in converted_sources:
            print(f"  Converted PDF -> TXT : {conv['converted_txt']}")
            print(f"  Converted PDF -> EPUB: {conv['converted_epub']}")
        print(f"  Mined candidate terms: {mined['total_candidates']} -> {mined['output_path']}")
        for c in meta_chunks:
            print(f"  - {c['chunk_id']}: {c['source_words']}w, {c['source_paragraphs']}p -> {c['source_chunk_path']}")
    return 0


# ---------------------------------------------------------------------------
# Subcommand: mine-terms (Whole-Book Entity & Term Mining)
# ---------------------------------------------------------------------------

_TERM_STOPWORDS = {
    "the", "a", "an", "this", "that", "these", "those", "there", "their", "they",
    "here", "where", "when", "while", "since", "because", "although", "however",
    "therefore", "meanwhile", "moreover", "furthermore", "nevertheless", "instead",
    "before", "after", "during", "under", "over", "between", "against", "through",
    "without", "within", "inside", "outside", "across", "around", "behind",
    "beneath", "beside", "beyond", "toward", "towards", "despite", "upon", "into",
    "onto", "near", "until", "unless", "once", "later", "soon", "perhaps",
    "suddenly", "still", "even", "only", "just", "almost", "always", "never",
    "often", "sometimes", "usually", "also", "next", "last", "several", "both",
    "another", "such", "what", "which", "who", "whom", "whose", "why", "how",
    "chapter", "section", "part", "page", "figure", "table", "appendix", "scene",
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
    "january", "february", "march", "april", "may", "june", "july", "august",
    "september", "october", "november", "december", "mr", "mrs", "ms", "dr",
    "sir", "lord", "lady", "yes", "no", "well", "now", "then", "but", "and",
    "for", "with", "from", "about", "first", "second", "third", "one", "two",
    "three", "all", "some", "many", "most", "each", "every", "other",
}
_ROMAN_NUMERALS = {"II", "III", "IV", "VI", "VII", "VIII", "IX", "XI", "XII"}


def mine_terms_ops(workspace: Path, top_n: int = 200, min_freq: int = 2) -> Dict[str, Any]:
    """Scan all source_chunks/*.md to extract recurring proper nouns, acronyms, and special terms."""
    chunks_dir = workspace / "source_chunks"
    if not chunks_dir.is_dir():
        raise FileNotFoundError(f"source_chunks directory not found in {workspace}")

    manifest_rows = read_csv_rows(workspace / "chunk-manifest.csv", MANIFEST_HEADER)
    ordered_ids = [r["chunk_id"] for r in manifest_rows if r.get("chunk_id")]
    chunk_files: List[Tuple[str, Path]] = []
    seen_files: Set[Path] = set()
    for cid in ordered_ids:
        fp = chunks_dir / f"{cid}.md"
        if fp.is_file():
            chunk_files.append((cid, fp))
            seen_files.add(fp)
    for fp in sorted(chunks_dir.glob("*.md"), key=lambda p: natural_sort_key(p.name)):
        if fp not in seen_files:
            chunk_files.append((fp.stem, fp))

    glossary_rows = read_csv_rows(workspace / "glossary.csv", GLOSSARY_HEADER)
    glossary_terms = {r.get("term", "").strip().lower() for r in glossary_rows if r.get("term", "").strip()}

    stats: Dict[str, Dict[str, Any]] = {}

    def _record(raw_term: str, cid: str, cat: str) -> None:
        clean = re.sub(r"\s+", " ", raw_term).strip(" ,.;:!?\"'“”‘’()[]{}")
        words = clean.split()
        while words and words[0].lower() in _TERM_STOPWORDS:
            words.pop(0)
        clean = " ".join(words)
        if len(clean) < 2 or len(clean) > 60:
            return
        if clean.lower() in _TERM_STOPWORDS or clean.upper() in _ROMAN_NUMERALS:
            return
        if clean.isdigit():
            return
        key = clean.lower()
        entry = stats.get(key)
        if entry is None:
            stats[key] = {
                "term": clean,
                "count": 1,
                "chunks": [cid],
                "first_chunk_id": cid,
                "category_guess": cat,
            }
        else:
            entry["count"] += 1
            if cid not in entry["chunks"]:
                entry["chunks"].append(cid)
            # Prefer properly cased multi-occurrence surface form and specific category
            if clean[0].isupper() and not entry["term"][0].isupper():
                entry["term"] = clean
            if cat == "acronym":
                entry["category_guess"] = "acronym"

    re_multi_cap = re.compile(
        r"\b([A-ZÀ-Ỹ][a-zA-ZÀ-ỹ'’-]{1,24}(?:\s+(?:of|the|and|de|von|van|[A-ZÀ-Ỹ][a-zA-ZÀ-ỹ'’-]{1,24})){1,4})\b"
    )
    re_mid_cap = re.compile(
        r"(?:[a-zà-ỹ0-9,;:\"'”»)\]]\s+)([A-ZÀ-Ỹ][a-zà-ỹ'’-]{2,24})\b"
    )
    re_acronym = re.compile(r"\b([A-Z]{2,}[A-Z0-9-]{0,8})\b")
    re_cjk_bracket = re.compile(r"[《〈「『【]([^》〉」』】\n]{2,15})[》〉」』】]")
    re_italic = re.compile(r"(?<!\*)\*([^*\n`]{3,35})\*(?!\*)")

    for cid, fp in chunk_files:
        raw = _strip_block_anchors(fp.read_text(encoding="utf-8", errors="replace"))
        no_code = re.sub(r"(?s)(?:```|~~~).*?(?:```|~~~)", " ", raw)
        no_code = re.sub(r"`[^`\n]+`", " ", no_code)
        no_links = re.sub(r"\]\([^)]+\)", "]", no_code)

        for m in re_acronym.finditer(no_links):
            _record(m.group(1), cid, "acronym")
        for m in re_multi_cap.finditer(no_links):
            phrase = m.group(1)
            # Ensure last word is capitalized and not just "The X of"
            last_tok = phrase.split()[-1]
            if last_tok[:1].isupper() and len(phrase.split()) >= 2:
                _record(phrase, cid, "proper-noun")
        for m in re_mid_cap.finditer(no_links):
            _record(m.group(1), cid, "proper-noun")
        for m in re_cjk_bracket.finditer(no_links):
            _record(m.group(1), cid, "quoted-term")
        for m in re_italic.finditer(no_links):
            val = m.group(1).strip()
            if len(val.split()) <= 4:
                _record(val, cid, "italicized-term")

    candidates: List[Dict[str, Any]] = []
    for key, info in stats.items():
        if info["count"] < min_freq and not (len(info["chunks"]) >= 2):
            continue
        candidates.append({
            "term": info["term"],
            "count": info["count"],
            "chunk_count": len(info["chunks"]),
            "chunks": info["chunks"],
            "first_chunk_id": info["first_chunk_id"],
            "category_guess": info["category_guess"],
            "in_glossary": key in glossary_terms,
        })

    candidates.sort(key=lambda c: (-c["chunk_count"], -c["count"], c["term"].lower()))
    candidates = candidates[:max(1, top_n)]

    out_path = workspace / "candidate-terms.json"
    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "chunks_scanned": len(chunk_files),
        "min_freq": min_freq,
        "total_candidates": len(candidates),
        "unsolved_candidates": sum(1 for c in candidates if not c["in_glossary"]),
        "candidates": candidates,
    }
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return {
        "output_path": str(out_path),
        "chunks_scanned": len(chunk_files),
        "total_candidates": len(candidates),
        "unsolved_candidates": payload["unsolved_candidates"],
        "candidates": candidates,
    }


def cmd_mine_terms(args: argparse.Namespace, pack_root: Path) -> int:
    workspace = Path(args.workspace).expanduser().resolve()
    if not workspace.is_dir():
        print(f"Error: workspace directory does not exist: {workspace}", file=sys.stderr)
        return 1
    try:
        res = mine_terms_ops(workspace, top_n=args.top, min_freq=args.min_freq)
    except Exception as exc:
        print(f"Error mining terms: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps({"command": "mine-terms", **res}, indent=2, ensure_ascii=False))
    else:
        print(f"Mined {res['total_candidates']} candidate term(s) across {res['chunks_scanned']} chunk(s) -> {res['output_path']}")
        for c in res["candidates"][:20]:
            mark = "glossary" if c["in_glossary"] else "new"
            print(f"  - {c['term']} [{c['category_guess']}] count={c['count']} chunks={c['chunk_count']} ({mark})")
    return 0


# ---------------------------------------------------------------------------
# Subcommand: bundle-chunk (Scoped Worker Prompt Packet Builder)
# ---------------------------------------------------------------------------

def _filter_markdown_table_rows(md_text: str, match_corpus_low: str, max_fallback_lines: int = 55) -> str:
    """Keep Markdown headings and table rows relevant to match_corpus_low (or full text if compact)."""
    lines = md_text.splitlines()
    if len(lines) <= max_fallback_lines:
        return md_text.strip()

    kept: List[str] = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        if s.startswith("|") and i + 1 < len(lines) and re.match(r"^\s*\|[\s:-]+\|", lines[i + 1]):
            header = ln
            sep = lines[i + 1]
            matched_rows: List[str] = []
            j = i + 2
            while j < len(lines) and lines[j].strip().startswith("|"):
                row_txt = lines[j].strip()
                cells = [c.strip().lower() for c in row_txt.strip("|").split("|") if c.strip()]
                if any(len(cell) >= 3 and cell in match_corpus_low for cell in cells[:2]) or "all" in cells[:2]:
                    matched_rows.append(lines[j])
                j += 1
            if matched_rows:
                kept.extend([header, sep, *matched_rows])
            i = j
            continue
        if s.startswith("#") or s.startswith("- "):
            kept.append(ln)
        i += 1
    return "\n".join(kept).strip()


def bundle_chunk_ops(
    pack_root: Path,
    workspace: Path,
    chunk_id: str,
    role: str = "chunk-translator",
    out_path: Optional[Path] = None,
) -> Dict[str, Any]:
    """Assemble a scoped worker prompt packet with Contract Card and chunk-filtered artifact slices."""
    manifest_rows = read_csv_rows(workspace / "chunk-manifest.csv", MANIFEST_HEADER)
    row_idx: Optional[int] = None
    for idx, r in enumerate(manifest_rows):
        if r.get("chunk_id", "").strip() == chunk_id:
            row_idx = idx
            break
    if row_idx is None:
        raise ValueError(f"Chunk '{chunk_id}' not found in {workspace / 'chunk-manifest.csv'}")

    row = manifest_rows[row_idx]
    prev_id = manifest_rows[row_idx - 1]["chunk_id"] if row_idx > 0 else ""
    next_id = manifest_rows[row_idx + 1]["chunk_id"] if row_idx + 1 < len(manifest_rows) else ""

    src_chunk_path = workspace / "source_chunks" / f"{chunk_id}.md"
    if not src_chunk_path.is_file():
        raise FileNotFoundError(f"Source chunk file not found: {src_chunk_path}")
    source_text = src_chunk_path.read_text(encoding="utf-8", errors="replace").strip()

    out_rel = row.get("output_path", "").strip() or f"output/{chunk_id}.md"
    target_file = Path(out_rel) if Path(out_rel).is_absolute() else (workspace / out_rel)
    target_text = target_file.read_text(encoding="utf-8", errors="replace").strip() if target_file.is_file() else ""

    match_corpus = _strip_block_anchors(source_text) + "\n" + target_text
    match_corpus_low = match_corpus.lower()

    version = read_pack_version(pack_root)
    role_prompt_rel = f"core/prompts/{role}.md"
    contract_card = (
        f"WORKER CONTRACT CARD — d-transcreate {version}. Read this first.\n\n"
        f"1. Stay in role. You are {role} for scope {chunk_id}. Do exactly this scope,\n"
        "   nothing outside it, even if adjacent text or issues are visible.\n"
        f"2. Read your full role prompt at {role_prompt_rel} — the path is\n"
        "   relative to the project root. If you cannot read it, STOP and return\n"
        "   blocked: missing-role-prompt instead of improvising.\n"
        "3. Propose, never write. Write ONLY the output paths listed in your dispatch\n"
        "   unit. Never edit the Glossary, Style_Sheet, Story_Bible, Domain_Map,\n"
        "   Chunk_Manifest, Unresolved_Issues_Log, or another worker's files. Return\n"
        "   proposals and unresolved_items in your structured output; the Coordinator\n"
        "   is the only writer of shared artifacts.\n"
        "4. Never guess. Preserve formal data, follow approved Glossary/Style_Sheet slices,\n"
        "   respect reveal timing, use severity scale critical/major/minor, report\n"
        "   context_pressure honestly, and return ALL output contract fields."
    )

    # Synced Glossary slice (glossary.csv + pending glossary-inbox.jsonl)
    glossary_rows = read_csv_rows(workspace / "glossary.csv", GLOSSARY_HEADER)
    matched_glossary: List[Dict[str, str]] = []
    for gr in glossary_rows:
        term = gr.get("term", "").strip()
        pref = gr.get("preferred_translation", "").strip()
        forb = gr.get("forbidden_translation", "").strip()
        hit = bool(term and _phrase_pattern(term).search(match_corpus))
        if not hit and target_text:
            for variant in [p.strip() for p in pref.split(";") + forb.split(";") if p.strip()]:
                if _phrase_pattern(variant).search(target_text):
                    hit = True
                    break
        if hit:
            matched_glossary.append(gr)

    inbox_path = workspace / "glossary-inbox.jsonl"
    if inbox_path.is_file():
        seen_terms = {r["term"].lower() for r in matched_glossary}
        for raw_ln in inbox_path.read_text(encoding="utf-8", errors="replace").splitlines():
            s = raw_ln.strip()
            if not s:
                continue
            try:
                obj = json.loads(s)
            except json.JSONDecodeError:
                continue
            term = str(obj.get("term", "")).strip()
            if term and term.lower() not in seen_terms and _phrase_pattern(term).search(match_corpus):
                matched_glossary.append({
                    "term": term,
                    "preferred_translation": str(obj.get("preferred_translation", "")).strip(),
                    "forbidden_translation": str(obj.get("forbidden_translation", "")).strip(),
                    "term_class": str(obj.get("term_class", "concept")).strip(),
                    "context": str(obj.get("context", "")).strip(),
                    "source_location": "inbox",
                    "evidence": str(obj.get("evidence", "inbox")).strip(),
                    "confidence": str(obj.get("confidence", "medium")).strip(),
                    "status": "proposed-inbox",
                    "notes": str(obj.get("notes", "")).strip(),
                })
                seen_terms.add(term.lower())

    glossary_table_lines = [
        "| term | preferred_translation | forbidden_translation | term_class | status | notes |",
        "|---|---|---|---|---|---|",
    ]
    for mr in matched_glossary:
        glossary_table_lines.append(
            "| " + " | ".join(
                str(mr.get(col, "")).replace("|", "\\|")
                for col in ("term", "preferred_translation", "forbidden_translation", "term_class", "status", "notes")
            ) + " |"
        )
    if len(matched_glossary) == 0:
        glossary_table_lines.append("| (no matching glossary terms in this chunk) | - | - | - | - | - |")

    brief_txt = (workspace / "translation-brief.md").read_text(encoding="utf-8", errors="replace").strip() if (workspace / "translation-brief.md").is_file() else ""
    dossier_txt = (workspace / "research-dossier.md").read_text(encoding="utf-8", errors="replace").strip() if (workspace / "research-dossier.md").is_file() else ""
    dossier_slice = _filter_markdown_table_rows(dossier_txt, match_corpus_low, max_fallback_lines=45) if dossier_txt else ""
    style_txt = (workspace / "style-sheet.md").read_text(encoding="utf-8", errors="replace").strip() if (workspace / "style-sheet.md").is_file() else ""

    continuity_slice_parts: List[str] = []
    for fname, title_lbl in (("story-bible.md", "Story Bible Slice"), ("domain-map.md", "Domain Map Slice")):
        fp = workspace / fname
        if fp.is_file():
            raw_c = fp.read_text(encoding="utf-8", errors="replace").strip()
            filtered_c = _filter_markdown_table_rows(raw_c, match_corpus_low, max_fallback_lines=45)
            if filtered_c:
                continuity_slice_parts.append(f"## {title_lbl}\n\n{filtered_c}")

    def _load_summary(cid_ref: str) -> str:
        if not cid_ref:
            return ""
        sp = workspace / "summaries" / f"{cid_ref}.md"
        if sp.is_file():
            return sp.read_text(encoding="utf-8", errors="replace").strip()
        return ""

    prev_summary = _load_summary(prev_id)
    next_summary = _load_summary(next_id)

    unresolved_slice = ""
    ui_path = workspace / "unresolved-issues.md"
    if ui_path.is_file():
        ui_lines = ui_path.read_text(encoding="utf-8", errors="replace").splitlines()
        matched_ui = [
            ln for ln in ui_lines
            if ln.strip().startswith("|") and (chunk_id.lower() in ln.lower() or "open" in ln.lower())
        ]
        if len(matched_ui) > 2:
            unresolved_slice = "\n".join(matched_ui)

    sections = [
        f"# Worker Packet: {chunk_id} ({role})",
        "```text\n" + contract_card + "\n```",
        f"## Chunk Metadata\n- chunk_id: `{chunk_id}`\n- role: `{role}`\n- semantic_unit: {row.get('semantic_unit', '')}\n- source_location: {row.get('source_location', '')}\n- output_path: `{out_rel}`",
    ]
    if brief_txt:
        sections.append("## Translation Brief\n\n" + brief_txt)
    if dossier_slice:
        sections.append("## Research Dossier Slice\n\n" + dossier_slice)
    sections.append("## Glossary Slice\n\n" + "\n".join(glossary_table_lines))
    if style_txt:
        sections.append("## Style Sheet\n\n" + style_txt)
    if continuity_slice_parts:
        sections.extend(continuity_slice_parts)
    if prev_summary:
        sections.append(f"## Previous Chunk Summary ({prev_id})\n\n{prev_summary}")
    if next_summary:
        sections.append(f"## Next Chunk Summary ({next_id})\n\n{next_summary}")
    if unresolved_slice:
        sections.append("## Scoped Unresolved Issues\n\n" + unresolved_slice)

    sections.append(
        "## Source Chunk\n\n"
        "_Preserve any `<!-- @bN -->` block anchor lines and Markdown links `[label](href)` verbatim._\n\n"
        + source_text
    )
    if role != "chunk-translator" and target_text:
        sections.append(f"## Target Chunk ({chunk_id})\n\n{target_text}")

    packet_content = "\n\n---\n\n".join(sections) + "\n"
    dest = out_path if out_path else (workspace / "packets" / f"{chunk_id}-{role}.md")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(packet_content, encoding="utf-8")

    return {
        "chunk_id": chunk_id,
        "role": role,
        "packet_path": str(dest),
        "matched_glossary_rows": len(matched_glossary),
        "packet_words": count_words(packet_content),
    }


def cmd_bundle_chunk(args: argparse.Namespace, pack_root: Path) -> int:
    workspace = Path(args.workspace).expanduser().resolve()
    if not workspace.is_dir():
        print(f"Error: workspace directory does not exist: {workspace}", file=sys.stderr)
        return 1
    out_p = Path(args.out).expanduser().resolve() if args.out else None
    try:
        res = bundle_chunk_ops(
            pack_root=pack_root,
            workspace=workspace,
            chunk_id=args.chunk,
            role=args.role,
            out_path=out_p,
        )
    except Exception as exc:
        print(f"Error building worker packet: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps({"command": "bundle-chunk", **res}, indent=2, ensure_ascii=False))
    else:
        print(
            f"Bundled packet for {res['chunk_id']} ({res['role']}): "
            f"{res['matched_glossary_rows']} glossary row(s), {res['packet_words']}w -> {res['packet_path']}"
        )
    return 0


# ---------------------------------------------------------------------------
# Subcommand: convert
# ---------------------------------------------------------------------------

def _write_converted_output(
    out_path: Path,
    fmt: str,
    units: Sequence[Tuple[str, str, str]],
    title: str,
    author: str,
    lang: str,
) -> Path:
    """Write a converted book output file in txt, epub, or md format."""
    chapter_pairs = [(ch_title, body) for _loc, ch_title, body in units]
    toc_lines = [f"- {ch_title}" for ch_title, _body in chapter_pairs] if len(chapter_pairs) > 1 else None
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if fmt == "epub":
        write_epub_book(out_path, chapter_pairs, title=title, author=author, lang=lang)
    elif fmt == "txt":
        out_path.write_text(render_plain_txt(chapter_pairs, toc_lines=toc_lines, title=title), encoding="utf-8")
    else:
        parts = [f"# {title}"]
        if toc_lines:
            parts.append("## Table of Contents\n\n" + "\n".join(toc_lines) + "\n\n---")
        parts.extend(body.strip() for _t, body in chapter_pairs if body.strip())
        out_path.write_text("\n\n".join(parts).rstrip() + "\n", encoding="utf-8")
    return out_path


def cmd_convert(args: argparse.Namespace, pack_root: Path) -> int:
    source_path = Path(args.source).expanduser().resolve()
    if not source_path.exists():
        print(f"Error: source path does not exist: {source_path}", file=sys.stderr)
        return 1

    try:
        units, _ = _collect_source_units(source_path, convert_dir=None)
    except Exception as exc:
        print(f"Error converting source: {exc}", file=sys.stderr)
        return 1

    if not units:
        print(f"Error: no readable content found in {source_path}", file=sys.stderr)
        return 1

    title = args.title or source_path.stem
    author = args.author or "Source Document"
    lang = args.lang or "und"
    outputs_written: List[str] = []

    if args.out:
        out_path = Path(args.out).expanduser().resolve()
        ext = out_path.suffix.lower()
        fmt = args.format if args.format != "auto" else (
            "epub" if ext == ".epub" else ("txt" if ext == ".txt" else "md")
        )
        if fmt == "both":
            stem = out_path.with_suffix("")
            outputs_written.append(str(_write_converted_output(stem.with_suffix(".txt"), "txt", units, title, author, lang)))
            outputs_written.append(str(_write_converted_output(stem.with_suffix(".epub"), "epub", units, title, author, lang)))
        else:
            outputs_written.append(str(_write_converted_output(out_path, fmt, units, title, author, lang)))

    if args.also_out:
        also_path = Path(args.also_out).expanduser().resolve()
        ext2 = also_path.suffix.lower()
        fmt2 = "epub" if ext2 == ".epub" else ("txt" if ext2 == ".txt" else "md")
        outputs_written.append(str(_write_converted_output(also_path, fmt2, units, title, author, lang)))

    if args.out_dir:
        out_dir = Path(args.out_dir).expanduser().resolve()
        safe_stem = slugify_id(source_path.stem)
        outputs_written.append(str(_write_converted_output(out_dir / f"{safe_stem}.txt", "txt", units, title, author, lang)))
        outputs_written.append(str(_write_converted_output(out_dir / f"{safe_stem}.epub", "epub", units, title, author, lang)))

    if not outputs_written:
        print("Error: provide --out or --out-dir", file=sys.stderr)
        return 1

    result = {
        "command": "convert",
        "source": str(source_path),
        "sections": len(units),
        "words": sum(count_words(u[2]) for u in units),
        "outputs": outputs_written,
    }
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"Converted {source_path} ({len(units)} section(s)):")
        for out_f in outputs_written:
            print(f"  -> {out_f}")
    return 0


# ---------------------------------------------------------------------------
# Subcommand: sync-glossary
# ---------------------------------------------------------------------------

def cmd_sync_glossary(args: argparse.Namespace, pack_root: Path) -> int:
    workspace = Path(args.workspace).expanduser().resolve()
    if not workspace.is_dir():
        print(f"Error: workspace directory does not exist: {workspace}", file=sys.stderr)
        return 1

    try:
        res = sync_glossary_ops(
            pack_root=pack_root,
            workspace=workspace,
            memory_arg=args.memory,
            seed=args.seed,
            promote=args.promote,
            target_lang=args.target_lang,
            domain=args.domain,
            filter_to_source=args.filter_to_source,
            approve_clean=args.approve_clean,
            include_proper_nouns=args.include_proper_nouns,
        )
    except Exception as exc:
        print(f"Error syncing glossary: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps({"command": "sync-glossary", **res}, indent=2, ensure_ascii=False))
    else:
        print(f"Glossary synced: {res['glossary_path']}")
        print(
            f"  Seeded: {res['seeded']} (domain skipped: {res['domain_skipped']}), "
            f"Pruned unused: {res['pruned_unused']}, Inbox added: {res['inbox_added']}, "
            f"Auto-approved: {res['auto_approved']}, Promoted: {res['promoted']} "
            f"(project-specific skipped: {res['promoted_skipped_project_specific']})"
        )
        print(f"  Total project rows: {res['total_project_rows']}")
        for c in res["conflicts"]:
            print(f"  CONFLICT ({c['term']}): existing='{c['existing_preferred']}' vs incoming='{c['incoming_preferred']}'")
        for w in res["warnings"]:
            print(f"  WARN: {w}")
    return 0


# ---------------------------------------------------------------------------
# Subcommand: verify
# ---------------------------------------------------------------------------

def _phrase_pattern(phrase: str) -> re.Pattern:
    return re.compile(r"(?<!\w)" + re.escape(phrase) + r"(?!\w)", re.IGNORECASE | re.UNICODE)


def _check_unclosed_code_fences(text: str) -> bool:
    fence_count = 0
    for line in text.splitlines():
        if re.match(r"^\s*```", line):
            fence_count += 1
    return (fence_count % 2) != 0


def _read_brief_context(workspace: Path) -> Dict[str, str]:
    """Read source_lang, target_lang, and inferred domain from translation-brief.md."""
    info = {"source_lang": "", "target_lang": "", "domain": "all"}
    brief = workspace / "translation-brief.md"
    if not brief.is_file():
        return info
    txt = brief.read_text(encoding="utf-8", errors="replace")
    for line in txt.splitlines():
        m_src = re.match(r"^\s*-\s*Source language:\s*(.+)$", line, re.IGNORECASE)
        if m_src and m_src.group(1).strip():
            pref, _ = resolve_lang_info(m_src.group(1).strip())
            info["source_lang"] = pref
        m_tgt = re.match(r"^\s*-\s*Target language:\s*(.+)$", line, re.IGNORECASE)
        if m_tgt and m_tgt.group(1).strip():
            pref, _ = resolve_lang_info(m_tgt.group(1).strip())
            info["target_lang"] = pref

    low = txt.lower()
    if any(k in low for k in ("legal", "contract", "privacy policy", "statute", "compliance")):
        info["domain"] = "legal"
    elif any(k in low for k in ("technical", "api", "software", "kubernetes", "devops", "engineering", "manual")):
        info["domain"] = "technical"
    elif any(k in low for k in ("fiction", "novel", "fantasy", "wuxia", "xianxia", "story")):
        info["domain"] = "fiction"
    return info


def _check_dossier_completeness(workspace: Path) -> bool:
    """Return True if research-dossier.md has Phase 3 classification and mindset/audit content."""
    dossier_path = workspace / "research-dossier.md"
    if not dossier_path.is_file():
        return False
    text = dossier_path.read_text(encoding="utf-8", errors="replace")
    m_status = re.search(r"(?mi)^[ \t]*-[ \t]*prior_translation_status:[ \t]*(\S[^\r\n]*)$", text)
    has_status = bool(m_status and not m_status.group(1).strip().startswith("<"))
    m_mind = re.search(r"(?mi)^[ \t]*-[ \t]*mindset_summary:[ \t]*(\S[^\r\n]*)$", text)
    has_mindset = bool(m_mind and not m_mind.group(1).strip().startswith("<"))
    has_audit_row = False
    in_audit = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("## Existing Translations Audit"):
            in_audit = True
            continue
        if in_audit and s.startswith("## "):
            break
        if in_audit and s.startswith("|") and not s.startswith("| Edition") and not re.match(r"^\|[\s|-]+\|$", s):
            cells = [c.strip() for c in s.strip("|").split("|") if c.strip()]
            if cells:
                has_audit_row = True
                break
    return has_status and (has_mindset or has_audit_row)


def _strip_code_and_anchors(text: str) -> str:
    s = _strip_block_anchors(text)
    s = re.sub(r"(?s)(?:```|~~~).*?(?:```|~~~)", " ", s)
    return s


def _extract_prose_numbers(text: str) -> Set[str]:
    """Extract normalized multi-digit / decimal / percentage numbers from prose (outside code/headings/URLs)."""
    s = _strip_code_and_anchors(text)
    s = re.sub(r"(?m)^\s*#{1,6}\s+.*$", " ", s)
    s = re.sub(r"`[^`\n]+`", " ", s)
    s = re.sub(r"\]\([^)]+\)", "]", s)
    s = re.sub(r"https?://\S+", " ", s)
    raw_nums = re.findall(r"\b\d{2,}(?:[.,]\d+)*%?\b|\b\d+[.,]\d+%?\b", s)
    return {re.sub(r"[.,]", "", num) for num in raw_nums}


def run_verify(
    workspace: Path,
    min_word_ratio: Optional[float] = None,
    max_word_ratio: Optional[float] = None,
    min_char_ratio: float = 0.5,
    strict: bool = False,
    require_dossier: bool = False,
    enforce_glossary: bool = False,
) -> Dict[str, Any]:
    """Run deterministic completeness, parity, dossier, formal-data, script-leakage, locale, and glossary checks."""
    errors: List[Dict[str, str]] = []
    warnings: List[Dict[str, str]] = []
    chunk_metrics: List[Dict[str, Any]] = []

    def add_finding(level: str, check: str, message: str, chunk_id: str = "") -> None:
        item = {"check": check, "level": level, "message": message}
        if chunk_id:
            item["chunk_id"] = chunk_id
        if level == "error":
            errors.append(item)
        else:
            warnings.append(item)

    brief_ctx = _read_brief_context(workspace)
    src_lang = brief_ctx["source_lang"]
    tgt_lang = brief_ctx["target_lang"]
    inferred_domain = brief_ctx["domain"]

    if min_word_ratio is None:
        min_word_ratio = 0.48 if (src_lang == "vi" and tgt_lang in {"en", "fr", "de", "es"}) else 0.65
    if max_word_ratio is None:
        max_word_ratio = 2.8 if (tgt_lang == "vi" and src_lang != "vi") else 2.5

    dossier_complete = _check_dossier_completeness(workspace)
    if require_dossier and not dossier_complete:
        add_finding(
            "error",
            "dossier",
            "Research_Dossier (research-dossier.md) is incomplete: missing prior_translation_status or mindset/audit entries",
        )

    manifest_path = workspace / "chunk-manifest.csv"
    if not manifest_path.is_file():
        add_finding("error", "completeness", "Missing chunk-manifest.csv")
        return {
            "passed": False,
            "dossier_complete": dossier_complete,
            "errors": errors,
            "warnings": warnings,
            "chunk_metrics": chunk_metrics,
        }

    manifest_rows = read_csv_rows(manifest_path, MANIFEST_HEADER)
    if not manifest_rows:
        add_finding("error", "completeness", "chunk-manifest.csv contains no chunk rows")
        return {
            "passed": False,
            "dossier_complete": dossier_complete,
            "errors": errors,
            "warnings": warnings,
            "chunk_metrics": chunk_metrics,
        }

    meta_by_id: Dict[str, Dict[str, Any]] = {}
    meta_path = workspace / ".book-scan-meta.json"
    if meta_path.is_file():
        try:
            meta_data = json.loads(meta_path.read_text(encoding="utf-8"))
            for c in meta_data.get("chunks", []):
                if isinstance(c, dict) and c.get("chunk_id"):
                    meta_by_id[c["chunk_id"]] = c
        except (json.JSONDecodeError, OSError) as exc:
            add_finding("error", "completeness", f"Corrupt .book-scan-meta.json: {exc}")

    manifest_ids = {r["chunk_id"] for r in manifest_rows if r.get("chunk_id")}
    for cid in sorted(meta_by_id):
        if cid not in manifest_ids:
            add_finding("error", "completeness", f"Scanned chunk '{cid}' missing from chunk-manifest.csv", cid)

    glossary_rows = read_csv_rows(workspace / "glossary.csv", GLOSSARY_HEADER)

    # Pre-compile forbidden & approved glossary matchers
    forbidden_matchers: List[Tuple[str, str, re.Pattern]] = []
    approved_matchers: List[Tuple[str, bool, re.Pattern, List[Tuple[str, re.Pattern]]]] = []
    for gr in glossary_rows:
        term = gr.get("term", "").strip()
        pref = gr.get("preferred_translation", "").strip()
        forb_raw = gr.get("forbidden_translation", "").strip()
        src_loc = gr.get("source_location", "").strip().lower()
        is_mem_seed = src_loc == "memory-seed"

        if forb_raw:
            for forb in forb_raw.split(";"):
                f_clean = forb.strip()
                if f_clean:
                    forbidden_matchers.append((term, f_clean, _phrase_pattern(f_clean)))
        if gr.get("status", "").lower() == "approved" and term and pref:
            if is_mem_seed and inferred_domain != "all" and not _row_matches_domain(gr, inferred_domain):
                continue
            pref_variants = [p.strip() for p in pref.split(";") if p.strip()]
            approved_matchers.append((
                term,
                is_mem_seed,
                _phrase_pattern(term),
                [(pv, _phrase_pattern(pv)) for pv in pref_variants],
            ))

    term_applied_chunks: Dict[str, List[str]] = {}
    term_missing_chunks: Dict[str, List[Tuple[str, str]]] = {}
    vi_dialogue_styles: Dict[str, Set[str]] = {"em_dash": set(), "double_quote": set()}
    non_cjk_targets = {"vi", "en", "fr", "de", "es"}

    for row in manifest_rows:
        cid = row.get("chunk_id", "").strip()
        status = row.get("status", "").strip().lower()
        out_rel = row.get("output_path", "").strip()

        if status != "done":
            add_finding("error", "completeness", f"Chunk status is '{status}' (expected 'done')", cid)

        if not out_rel:
            add_finding("error", "completeness", "Chunk has empty output_path", cid)
            continue

        out_path = Path(out_rel)
        if not out_path.is_absolute():
            out_path = workspace / out_rel
        if not out_path.is_file():
            add_finding("error", "completeness", f"Translated output file missing: {out_rel}", cid)
            continue

        target_text = out_path.read_text(encoding="utf-8", errors="replace")
        if not _strip_block_anchors(target_text).strip():
            add_finding("error", "completeness", f"Translated output file is empty: {out_rel}", cid)
            continue

        t_words = count_words(target_text)
        t_chars = count_chars(target_text)
        t_paras = count_paragraphs(target_text)
        t_headings = count_headings(target_text)

        meta = meta_by_id.get(cid, {})
        source_text = ""
        src_chunk_rel = meta.get("source_chunk_path") or f"source_chunks/{cid}.md"
        src_chunk_path = workspace / src_chunk_rel
        if src_chunk_path.is_file():
            source_text = src_chunk_path.read_text(encoding="utf-8", errors="replace")

        s_words = int(meta.get("source_words", count_words(source_text) if source_text else 0))
        s_chars = int(meta.get("source_chars", count_chars(source_text) if source_text else 0))
        s_paras = int(meta.get("source_paragraphs", count_paragraphs(source_text) if source_text else 0))
        s_headings = int(meta.get("source_headings", count_headings(source_text) if source_text else 0))

        word_ratio = t_words / max(1, s_words) if s_words > 0 else 1.0
        char_ratio = t_chars / max(1, s_chars) if s_chars > 0 else 1.0

        chunk_metrics.append({
            "chunk_id": cid,
            "source_words": s_words,
            "target_words": t_words,
            "word_ratio": round(word_ratio, 3),
            "char_ratio": round(char_ratio, 3),
            "source_paragraphs": s_paras,
            "target_paragraphs": t_paras,
            "source_headings": s_headings,
            "target_headings": t_headings,
        })

        # Check 2: Length, Paragraph & Heading Parity
        if s_words > 0 or s_chars > 0:
            if s_words < 20 and s_chars > 100:
                if char_ratio < min_char_ratio:
                    add_finding(
                        "error",
                        "parity",
                        f"Char ratio {char_ratio:.2f} below min_char_ratio {min_char_ratio:.2f} "
                        f"({t_chars}/{s_chars} chars)",
                        cid,
                    )
            else:
                if word_ratio < min_word_ratio:
                    add_finding(
                        "error",
                        "parity",
                        f"Word ratio {word_ratio:.2f} below min_word_ratio {min_word_ratio:.2f} "
                        f"({t_words}/{s_words} words — possible omission/summarization)",
                        cid,
                    )
                if s_words >= 20 and word_ratio > max_word_ratio:
                    lvl = "error" if strict else "warning"
                    add_finding(
                        lvl,
                        "parity",
                        f"Word ratio {word_ratio:.2f} exceeds max_word_ratio {max_word_ratio:.2f} "
                        f"({t_words}/{s_words} words)",
                        cid,
                    )

        if s_headings > 0 and t_headings < s_headings:
            lvl = "error" if strict else "warning"
            add_finding(
                lvl,
                "parity",
                f"Heading count dropped from {s_headings} (source) to {t_headings} (target)",
                cid,
            )

        if s_paras >= 4 and t_paras < s_paras * 0.65:
            add_finding(
                "error",
                "parity",
                f"Paragraph count {t_paras} is below 65% of source paragraphs ({s_paras})",
                cid,
            )

        # Check 3: Anti-Truncation & Placeholder Scan
        for pat, label in _UNFINISHED_PATTERNS:
            if pat.search(target_text):
                add_finding("error", "placeholder", f"Unfinished marker detected: {label}", cid)

        if _check_unclosed_code_fences(target_text):
            add_finding("error", "placeholder", "Unclosed fenced code block (```)", cid)

        # Check 4: Glossary Compliance
        for term, forb_phrase, forb_re in forbidden_matchers:
            if forb_re.search(target_text):
                add_finding(
                    "error",
                    "glossary",
                    f"Forbidden translation '{forb_phrase}' (for term '{term}') found in output",
                    cid,
                )

        if source_text:
            s_no_anchors = _strip_block_anchors(source_text)
            for term, is_mem_seed, term_re, pref_patterns in approved_matchers:
                if term_re.search(s_no_anchors):
                    if any(pr.search(target_text) for _, pr in pref_patterns):
                        term_applied_chunks.setdefault(term, []).append(cid)
                    else:
                        expected_str = " / ".join(pv for pv, _ in pref_patterns)
                        term_missing_chunks.setdefault(term, []).append((cid, expected_str))
                        lvl = "error" if (strict or (enforce_glossary and not is_mem_seed)) else "warning"
                        add_finding(
                            lvl,
                            "glossary",
                            f"Approved term '{term}' in source missing preferred translation '{expected_str}'",
                            cid,
                        )

            # Check 5: Formal Data Parity (URLs, EPUB anchors, multi-digit numbers)
            s_clean = _strip_code_and_anchors(source_text)
            src_urls = {u.rstrip(".,;:!?") for u in re.findall(r"https?://[^\s)>\]\"'`]+", s_clean)}
            for url in sorted(src_urls):
                if url not in target_text:
                    add_finding("error", "formal-data", f"Source URL missing in target output: {url}", cid)

            if meta.get("epub_href"):
                src_fn_refs = set(re.findall(r"\]\(([^)\s]+#[A-Za-z0-9_.-]+)\)", s_clean))
                for ref_href in sorted(src_fn_refs):
                    if ref_href not in target_text:
                        lvl = "error" if strict else "warning"
                        add_finding(lvl, "formal-data", f"EPUB inline link target missing: {ref_href}", cid)

            s_nums = _extract_prose_numbers(source_text)
            t_nums = _extract_prose_numbers(target_text)
            missing_nums = sorted(s_nums - t_nums)
            if missing_nums:
                lvl = "error" if strict else "warning"
                add_finding(
                    lvl,
                    "formal-data",
                    f"Numeric value(s) from source missing in target: {', '.join(missing_nums[:5])}",
                    cid,
                )

        # Check 6: Untranslated CJK Script Leakage (for non-CJK target languages)
        if tgt_lang in non_cjk_targets:
            t_leak_scan = _strip_code_and_anchors(target_text)
            t_leak_scan = re.sub(r"`[^`\n]+`", " ", t_leak_scan)
            t_leak_scan = re.sub(r"\([^)\n]{1,45}\)", " ", t_leak_scan)
            m_cjk = re.search(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]{2,}", t_leak_scan)
            if m_cjk:
                add_finding(
                    "error",
                    "script-leakage",
                    f"Untranslated CJK script detected in '{tgt_lang}' output: '{m_cjk.group(0)[:20]}'",
                    cid,
                )

        # Check 7: Vietnamese Locale Linter
        if tgt_lang == "vi":
            t_no_code = _strip_code_and_anchors(target_text)
            em_lines = len(re.findall(r"(?m)^\s*[—–]\s+\S", t_no_code))
            quote_paras = len(re.findall(r'(?m)^\s*[“"][^”"\n]{15,}[”"]', t_no_code))
            if em_lines >= 2 and quote_paras == 0:
                vi_dialogue_styles["em_dash"].add(cid)
            elif quote_paras >= 2 and em_lines == 0:
                vi_dialogue_styles["double_quote"].add(cid)

            calques = (
                len(re.findall(r"\bmột cách\s+\w+", t_no_code, re.IGNORECASE))
                + len(re.findall(r"\b(?:bị|được)\s+\w+(?:\s+\w+)?\s+bởi\b", t_no_code, re.IGNORECASE))
                + len(re.findall(r"\bđã và đang\b", t_no_code, re.IGNORECASE))
            )
            if calques >= 5 and (calques / max(1, t_words)) > 0.025:
                add_finding(
                    "warning",
                    "locale-vi",
                    f"High anti-translatorese calque density ({calques} occurrences in {t_words} words)",
                    cid,
                )

    # Retroactive cross-chunk glossary drift summary warning
    for term, applied_cids in term_applied_chunks.items():
        if term in term_missing_chunks and applied_cids:
            missed = [cid for cid, _exp in term_missing_chunks[term]]
            add_finding(
                "warning",
                "glossary-drift",
                f"Retroactive drift on '{term}': applied in {applied_cids[0]} but missed in {', '.join(missed[:5])}",
            )

    if tgt_lang == "vi" and vi_dialogue_styles["em_dash"] and vi_dialogue_styles["double_quote"]:
        add_finding(
            "warning",
            "locale-vi",
            f"Mixed Vietnamese dialogue punctuation across chunks: em-dash in "
            f"{sorted(vi_dialogue_styles['em_dash'])[:3]} vs quoted in {sorted(vi_dialogue_styles['double_quote'])[:3]}",
        )

    return {
        "passed": len(errors) == 0,
        "total_chunks": len(manifest_rows),
        "dossier_complete": dossier_complete,
        "errors": errors,
        "warnings": warnings,
        "chunk_metrics": chunk_metrics,
    }


def cmd_verify(args: argparse.Namespace, pack_root: Path) -> int:
    workspace = Path(args.workspace).expanduser().resolve()
    if not workspace.is_dir():
        print(f"Error: workspace directory does not exist: {workspace}", file=sys.stderr)
        return 1

    res = run_verify(
        workspace=workspace,
        min_word_ratio=args.min_word_ratio,
        max_word_ratio=args.max_word_ratio,
        min_char_ratio=args.min_char_ratio,
        strict=args.strict,
        require_dossier=args.require_dossier,
        enforce_glossary=args.enforce_glossary,
    )

    if args.json:
        print(json.dumps({"command": "verify", **res}, indent=2, ensure_ascii=False))
    else:
        status_str = "PASSED" if res["passed"] else "FAILED"
        print(f"Verification {status_str}: {res['total_chunks']} chunk(s) checked, "
              f"{len(res['errors'])} error(s), {len(res['warnings'])} warning(s)")
        for e in res["errors"]:
            loc = f" [{e['chunk_id']}]" if e.get("chunk_id") else ""
            print(f"  ERROR ({e['check']}){loc}: {e['message']}")
        for w in res["warnings"]:
            loc = f" [{w['chunk_id']}]" if w.get("chunk_id") else ""
            print(f"  WARN  ({w['check']}){loc}: {w['message']}")

    return 0 if res["passed"] else 1


# ---------------------------------------------------------------------------
# Subcommand: merge
# ---------------------------------------------------------------------------

def _extract_toc_entries(text: str) -> List[str]:
    entries: List[str] = []
    in_fence = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = re.match(r"^(#{1,3})\s+(.+)$", s)
        if m:
            level = len(m.group(1))
            title = m.group(2).strip()
            indent = "  " * (level - 1)
            entries.append(f"{indent}- {title}")
    return entries


def _update_qa_completeness_audit(qa_report_path: Path, audit_section: str) -> None:
    if qa_report_path.is_file():
        content = qa_report_path.read_text(encoding="utf-8", errors="replace")
    else:
        content = FALLBACK_TEMPLATES["qa-report.md"]

    marker = "## Completeness Audit"
    if marker in content:
        idx = content.index(marker)
        content = content[:idx].rstrip() + "\n\n" + audit_section.strip() + "\n"
    else:
        content = content.rstrip() + "\n\n" + audit_section.strip() + "\n"
    qa_report_path.write_text(content, encoding="utf-8")


def _read_brief_target_lang(workspace: Path) -> str:
    brief = workspace / "translation-brief.md"
    if not brief.is_file():
        return "en"
    for line in brief.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^\s*-\s*Target language:\s*(.+)$", line, re.IGNORECASE)
        if m and m.group(1).strip():
            prefix, _ = resolve_lang_info(m.group(1).strip())
            return prefix or "en"
    return "en"


def _write_merged_format(
    target_path: Path,
    fmt: str,
    chapter_pairs: Sequence[Tuple[str, str]],
    chunk_texts: Sequence[str],
    toc_lines: Sequence[str],
    title: str,
    author: str,
    lang: str,
    template_epub: Optional[Path] = None,
    chunks_by_href: Optional[Dict[str, List[Tuple[Optional[int], Optional[int], str]]]] = None,
    explicit_title: Optional[str] = None,
) -> Path:
    target_path.parent.mkdir(parents=True, exist_ok=True)
    if fmt == "epub":
        if template_epub and template_epub.is_file() and chunks_by_href:
            rebuild_epub_preserving_layout(
                template_epub=template_epub,
                out_path=target_path,
                chunks_by_href=chunks_by_href,
                lang=lang,
                explicit_title=explicit_title,
            )
        else:
            write_epub_book(target_path, chapter_pairs, title=title, author=author, lang=lang)
    elif fmt == "txt":
        target_path.write_text(
            render_plain_txt(chapter_pairs, toc_lines=toc_lines or None, title=title),
            encoding="utf-8",
        )
    else:
        parts: List[str] = []
        if toc_lines:
            parts.append("## Table of Contents\n\n" + "\n".join(toc_lines) + "\n\n---")
        parts.extend(_strip_block_anchors(ct) for ct in chunk_texts)
        target_path.write_text("\n\n".join(parts).rstrip() + "\n", encoding="utf-8")
    return target_path


def cmd_merge(args: argparse.Namespace, pack_root: Path) -> int:
    workspace = Path(args.workspace).expanduser().resolve()
    out_path = Path(args.out).expanduser().resolve()

    if not workspace.is_dir():
        print(f"Error: workspace directory does not exist: {workspace}", file=sys.stderr)
        return 1

    verify_res: Optional[Dict[str, Any]] = None
    if not args.no_verify:
        verify_res = run_verify(
            workspace=workspace,
            require_dossier=getattr(args, "require_dossier", False),
            enforce_glossary=getattr(args, "enforce_glossary", False),
        )
        if not verify_res["passed"]:
            if args.json:
                print(json.dumps({"command": "merge", "merged": False, "verify": verify_res}, indent=2, ensure_ascii=False))
            else:
                print("Merge aborted: verification failed.", file=sys.stderr)
                for e in verify_res["errors"]:
                    loc = f" [{e['chunk_id']}]" if e.get("chunk_id") else ""
                    print(f"  ERROR ({e['check']}){loc}: {e['message']}", file=sys.stderr)
            return 1

    manifest_rows = read_csv_rows(workspace / "chunk-manifest.csv", MANIFEST_HEADER)
    if not manifest_rows:
        print("Error: chunk-manifest.csv is missing or empty", file=sys.stderr)
        return 1

    template_epub: Optional[Path] = None
    meta_by_id: Dict[str, Dict[str, Any]] = {}
    meta_path = workspace / ".book-scan-meta.json"
    if meta_path.is_file():
        try:
            meta_obj = json.loads(meta_path.read_text(encoding="utf-8"))
            template_rel = meta_obj.get("source_epub_template")
            if template_rel:
                cand_tmpl = Path(template_rel)
                if not cand_tmpl.is_absolute():
                    cand_tmpl = workspace / cand_tmpl
                if cand_tmpl.is_file():
                    template_epub = cand_tmpl
            for cmeta in meta_obj.get("chunks", []):
                cid = str(cmeta.get("chunk_id", "")).strip()
                if cid:
                    meta_by_id[cid] = cmeta
        except Exception:
            template_epub = None
            meta_by_id = {}

    chunk_texts: List[str] = []
    chapter_pairs: List[Tuple[str, str]] = []
    toc_lines: List[str] = []
    chunks_by_href: Dict[str, List[Tuple[Optional[int], Optional[int], str]]] = {}
    total_target_words = 0

    for row in manifest_rows:
        cid = row.get("chunk_id", "").strip()
        out_rel = row.get("output_path", "").strip()
        if not out_rel:
            print(f"Error: chunk '{cid}' has no output_path", file=sys.stderr)
            return 1
        chunk_file = Path(out_rel) if Path(out_rel).is_absolute() else (workspace / out_rel)
        if not chunk_file.is_file():
            print(f"Error: missing chunk output file: {chunk_file}", file=sys.stderr)
            return 1
        text = chunk_file.read_text(encoding="utf-8", errors="replace").strip()
        if not text:
            print(f"Error: empty chunk output file: {chunk_file}", file=sys.stderr)
            return 1
        chunk_texts.append(text)
        fallback_title = row.get("semantic_unit", "").strip() or cid or "Chapter"
        ch_title = _first_heading_or_fallback(text, fallback_title)
        chapter_pairs.append((ch_title, text))
        total_target_words += count_words(text)
        chunk_toc = _extract_toc_entries(text)
        toc_lines.extend(chunk_toc if chunk_toc else [f"- {ch_title}"])

        cmeta = meta_by_id.get(cid, {})
        href = cmeta.get("epub_href")
        if href:
            chunks_by_href.setdefault(str(href), []).append(
                (cmeta.get("epub_block_start"), cmeta.get("epub_block_end"), text)
            )

    explicit_title = getattr(args, "title", None)
    title = explicit_title or out_path.stem or "Translated Book"
    author = getattr(args, "author", None) or "d-transcreate"
    lang = getattr(args, "lang", None) or _read_brief_target_lang(workspace)
    fmt = getattr(args, "format", "auto")
    if fmt == "auto":
        ext = out_path.suffix.lower()
        fmt = "epub" if ext == ".epub" else ("txt" if ext == ".txt" else "md")

    outputs_written: List[str] = []
    used_epub_preserve = False
    can_preserve_epub = bool(template_epub and template_epub.is_file() and chunks_by_href)

    if fmt == "both":
        stem = out_path.with_suffix("")
        outputs_written.append(str(_write_merged_format(stem.with_suffix(".txt"), "txt", chapter_pairs, chunk_texts, toc_lines, title, author, lang)))
        outputs_written.append(str(_write_merged_format(stem.with_suffix(".epub"), "epub", chapter_pairs, chunk_texts, toc_lines, title, author, lang, template_epub=template_epub, chunks_by_href=chunks_by_href, explicit_title=explicit_title)))
        if can_preserve_epub:
            used_epub_preserve = True
    else:
        outputs_written.append(str(_write_merged_format(out_path, fmt, chapter_pairs, chunk_texts, toc_lines, title, author, lang, template_epub=template_epub, chunks_by_href=chunks_by_href, explicit_title=explicit_title)))
        if fmt == "epub" and can_preserve_epub:
            used_epub_preserve = True

    also_out = getattr(args, "also_out", None)
    if also_out:
        also_p = Path(also_out).expanduser().resolve()
        ext2 = also_p.suffix.lower()
        fmt2 = "epub" if ext2 == ".epub" else ("txt" if ext2 == ".txt" else "md")
        outputs_written.append(str(_write_merged_format(also_p, fmt2, chapter_pairs, chunk_texts, toc_lines, title, author, lang, template_epub=template_epub, chunks_by_href=chunks_by_href, explicit_title=explicit_title)))
        if fmt2 == "epub" and can_preserve_epub:
            used_epub_preserve = True

    verify_status = "PASSED" if verify_res else "SKIPPED (--no-verify)"
    total_source_words = sum(m["source_words"] for m in verify_res["chunk_metrics"]) if verify_res else 0
    audit_section = (
        "## Completeness Audit\n"
        f"- Merged timestamp: {datetime.now(timezone.utc).isoformat()}\n"
        f"- Output path: {', '.join(outputs_written)}\n"
        f"- Chunks merged: {len(manifest_rows)}\n"
        f"- Verification status: {verify_status}\n"
        f"- Source words (verified): {total_source_words}\n"
        f"- Target words merged: {total_target_words}\n"
        f"- EPUB layout preserved: {'yes' if used_epub_preserve else 'no'}\n"
    )
    _update_qa_completeness_audit(workspace / "qa-report.md", audit_section)

    result = {
        "command": "merge",
        "merged": True,
        "out": outputs_written[0],
        "outputs": outputs_written,
        "format": fmt,
        "chunks_merged": len(manifest_rows),
        "target_words": total_target_words,
        "epub_layout_preserved": used_epub_preserve,
        "verification": verify_status,
    }
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"Merged {len(manifest_rows)} chunk(s) ({total_target_words} words) -> {', '.join(outputs_written)}")
        print(f"Updated Completeness Audit in {workspace / 'qa-report.md'}")
    return 0


# ---------------------------------------------------------------------------
# CLI Entrypoint
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--pack-root",
        default=argparse.SUPPRESS,
        help="Override path to the d-transcreate skill pack root",
    )
    common.add_argument(
        "--json",
        action="store_true",
        default=argparse.SUPPRESS,
        help="Emit machine-readable JSON output",
    )

    parser = argparse.ArgumentParser(
        description="Deterministic book translation pipeline CLI for d-transcreate.",
        parents=[common],
    )
    parser.set_defaults(pack_root=None, json=False)

    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    p_init = subparsers.add_parser("init", parents=[common], help="Initialize workspace and seed defaults")
    p_init.add_argument("--source", required=True, help="Source file or directory path")
    p_init.add_argument("--target-lang", required=True, help="Target language (e.g., vi, vi-VN, Vietnamese)")
    p_init.add_argument("--workspace", required=True, help="Workspace directory path")
    p_init.add_argument("--source-lang", default=None, help="Source language (optional)")
    p_init.add_argument("--mode", default=None, help="Translation mode override")
    p_init.add_argument("--audience", default=None, help="Target audience description")
    p_init.add_argument("--output-format", default=None, help="Output format preference (e.g., 'txt, epub')")
    p_init.add_argument("--domain", choices=["all", "fiction", "technical", "legal", "general"], default="all", help="Seed domain filter for Tier-1 glossary memory")

    p_convert = subparsers.add_parser("convert", parents=[common], help="Convert PDF/document to EPUB and/or plain TXT")
    p_convert.add_argument("--source", required=True, help="Source PDF, EPUB, HTML, Markdown, TXT, or directory")
    p_convert.add_argument("--out", default=None, help="Primary output path (.epub, .txt, or .md)")
    p_convert.add_argument("--also-out", default=None, help="Optional secondary output path (.txt or .epub)")
    p_convert.add_argument("--out-dir", default=None, help="Output directory to write both <stem>.txt and <stem>.epub")
    p_convert.add_argument("--format", choices=["auto", "txt", "epub", "md", "both"], default="auto", help="Output format override")
    p_convert.add_argument("--title", default=None, help="Book title metadata")
    p_convert.add_argument("--author", default=None, help="Book author metadata")
    p_convert.add_argument("--lang", default=None, help="Language code for EPUB metadata")

    p_scan = subparsers.add_parser("scan", parents=[common], help="Scan source and generate chunks + manifest")
    p_scan.add_argument("--source", required=True, help="Source file (incl. PDF/EPUB) or directory path")
    p_scan.add_argument("--workspace", required=True, help="Workspace directory path")
    p_scan.add_argument("--max-words", type=int, default=1500, help="Max words per chunk (default: 1500)")

    p_mine = subparsers.add_parser("mine-terms", parents=[common], help="Mine recurring entities, acronyms, and special terms across chunks")
    p_mine.add_argument("--workspace", required=True, help="Workspace directory path")
    p_mine.add_argument("--top", type=int, default=200, help="Maximum candidates to return (default: 200)")
    p_mine.add_argument("--min-freq", type=int, default=2, help="Minimum corpus frequency (default: 2)")

    p_bundle = subparsers.add_parser("bundle-chunk", parents=[common], help="Build a scoped worker packet for one chunk")
    p_bundle.add_argument("--workspace", required=True, help="Workspace directory path")
    p_bundle.add_argument("--chunk", required=True, help="Chunk ID from chunk-manifest.csv")
    p_bundle.add_argument("--role", choices=["chunk-translator", "fidelity-reviewer", "continuity-reviewer", "formatting-reviewer"], default="chunk-translator", help="Target worker role")
    p_bundle.add_argument("--out", default=None, help="Optional output packet file path")

    p_sync = subparsers.add_parser("sync-glossary", parents=[common], help="Sync glossary with memory and worker inbox")
    p_sync.add_argument("--workspace", required=True, help="Workspace directory path")
    p_sync.add_argument("--memory", default=None, help="Explicit Tier-1 memory CSV path")
    p_sync.add_argument("--seed", action="store_true", help="Import approved entries from Tier-1 memory CSV")
    p_sync.add_argument("--promote", action="store_true", help="Promote approved high-confidence rows to memory CSV")
    p_sync.add_argument("--target-lang", default=None, help="Target language for auto-detecting memory CSV")
    p_sync.add_argument("--domain", choices=["all", "fiction", "technical", "legal", "general"], default="all", help="Filter seeded memory rows by book domain")
    p_sync.add_argument("--filter-to-source", action="store_true", help="Prune memory-seed rows whose term never appears in source_chunks/")
    p_sync.add_argument("--approve-clean", action="store_true", help="Auto-approve non-conflicting high/medium confidence inbox proposals")
    p_sync.add_argument("--include-proper-nouns", action="store_true", help="Allow --promote to export proper-name/project-specific entities")

    p_verify = subparsers.add_parser("verify", parents=[common], help="Verify 100%% coverage, parity, dossier, formal data, and glossary rules")
    p_verify.add_argument("--workspace", required=True, help="Workspace directory path")
    p_verify.add_argument("--min-word-ratio", type=float, default=None, help="Minimum target/source word ratio (auto-calibrated by language pair if omitted)")
    p_verify.add_argument("--max-word-ratio", type=float, default=None, help="Maximum target/source word ratio (auto-calibrated by language pair if omitted)")
    p_verify.add_argument("--min-char-ratio", type=float, default=0.5, help="Minimum char ratio for no-space scripts")
    p_verify.add_argument("--strict", action="store_true", help="Escalate warnings to errors")
    p_verify.add_argument("--require-dossier", action="store_true", help="Fail if research-dossier.md is incomplete")
    p_verify.add_argument("--enforce-glossary", action="store_true", help="Treat missing project-approved glossary renderings as errors")

    p_merge = subparsers.add_parser("merge", parents=[common], help="Verify and merge translated chunks")
    p_merge.add_argument("--workspace", required=True, help="Workspace directory path")
    p_merge.add_argument("--out", required=True, help="Output path (.txt, .epub, .md, or stem with --format both)")
    p_merge.add_argument("--format", choices=["auto", "md", "txt", "epub", "both"], default="auto", help="Output format")
    p_merge.add_argument("--also-out", default=None, help="Optional secondary output file (.txt or .epub)")
    p_merge.add_argument("--title", default=None, help="Book title metadata (for EPUB/TXT)")
    p_merge.add_argument("--author", default=None, help="Author metadata (for EPUB)")
    p_merge.add_argument("--lang", default=None, help="Target language code (for EPUB)")
    p_merge.add_argument("--no-verify", action="store_true", help="Skip pre-merge verify check")
    p_merge.add_argument("--require-dossier", action="store_true", help="Require complete research-dossier.md during pre-merge verify")
    p_merge.add_argument("--enforce-glossary", action="store_true", help="Enforce project-approved glossary renderings during pre-merge verify")

    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    pack_root = resolve_pack_root(args.pack_root)

    dispatch = {
        "init": cmd_init,
        "convert": cmd_convert,
        "scan": cmd_scan,
        "mine-terms": cmd_mine_terms,
        "bundle-chunk": cmd_bundle_chunk,
        "sync-glossary": cmd_sync_glossary,
        "verify": cmd_verify,
        "merge": cmd_merge,
    }
    handler = dispatch[args.subcommand]
    return handler(args, pack_root)


if __name__ == "__main__":
    if sys.stdout.encoding != "utf-8":
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    if sys.stderr.encoding != "utf-8":
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
    sys.exit(main())
