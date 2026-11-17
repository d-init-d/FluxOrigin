# Embedded D-Transcreate v1.1.0 Engine

FluxOrigin v3.0 integrates the core **D-Transcreate v1.1.0** book translation architecture directly inside the desktop app:

- **Native Dart Core (`lib/`)**
  - `lib/utils/term_miner.dart`: Whole-book named entity, CJK bracket (`《…》`, `「…」`), acronym, and italicized term mining.
  - `lib/services/d_transcreate_service.dart`: Domain-filtered Tier-1 translation memory (`assets/d_transcreate/glossary_vi.csv`), chunk-scoped glossary slicing, authentic Vietnamese style/dossier directives (`assets/d_transcreate/vi_vn_profile.md`), and full D-Transcreate workspace artifact export (`workspaces/<book>/`).
  - `lib/services/epub_pipeline_service.dart`: Anchor-Locked Layout-Preserving EPUB DOM engine (`<!-- @bN -->`) with inline link/footnote and `<img>` restoration, unique `id=` attribute stripping on split dialogue paragraphs, and `<td>`/`<th>` grid preservation.
  - `lib/services/qa_verifier_service.dart`: Deterministic 5-pillar QA verification (`completeness`, `script-leakage`, `formal-data`, `glossary-compliance`, `locale-vi`).

- **Bundled CLI (`tools/d_transcreate/book_ops.py`)**
  - Standard D-Transcreate v1.1.0 Python 3.8+ zero-dependency CLI.
  - Automatically leveraged by FluxOrigin for advanced PDF ingestion (sliding-window running-header detection and footnote recovery) whenever `python3` / `python` is available on `PATH`, and usable standalone against any FluxOrigin exported workspace under `<ProjectFolder>/workspaces/<BookName>/`.
