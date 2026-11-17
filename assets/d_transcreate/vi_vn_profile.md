# Locale Profile: Vietnamese (`vi` / `vi-VN`)

Auto-load this profile whenever `Translation_Brief` specifies `target_language` as `vi`, `vi-VN`, or `Vietnamese`. Record project-specific overrides in `style-sheet.md` and `research-dossier.md`.

---

## 1. Vietnamese Pronoun and Terms of Address System

Vietnamese pronouns encode age, kinship, hierarchy, intimacy, gender, and emotional stance in every utterance. Never translate `I` and `you` mechanically as `tôi` and `bạn` across a book.

### 1.1 Core Axes

- **Age and Kinship**: `anh/em`, `chị/em`, `chú/cháu`, `bác/cháu`, `cô/cháu`, `ông/cháu`, `bà/cháu`, `bố-cha/con`, `mẹ-má/con`.
- **Hierarchy and Respect**: `ngài` (dignitary/official), `ông/bà` (formal adult), `quý vị` (plural formal audience), `thầy/con` or `thầy/em` (teacher-student), `sư phụ/đệ tử` (master-disciple), `bệ hạ / thần` (monarch-subject).
- **Intimacy and Peer Dynamics**: `cậu/tớ` (warm school/young-adult peers), `mình/cậu` or `anh/em` (affectionate), `mày/tao` (childhood best friends, street slang, or open hostility), `hắn/y/gã/mụ` (third-person distance, suspicion, or contempt).

### 1.2 Genre Presets

| Genre / Domain | Default Pronoun Baseline | Guidance |
|---|---|---|
| Historical / Fantasy / Wuxia / Xianxia | `ta/ngươi`, `tại hạ/các hạ`, `huynh/đệ`, `tỷ/muội`, `tiên sinh`, `tôn giả`, `bệ hạ` | Match period gravity and martial/court hierarchy; avoid modern urban pronouns (`cậu/tớ`, `bạn`) unless deliberate comic contrast. |
| Modern Western Fiction | `tôi/anh`, `anh/em`, `tôi/cô`, `cậu/tớ`, `mày/tao` | Infer age and intimacy from context and `Story_Bible`; reserve `tôi/bạn` for wary strangers, business equals, or cold politeness. |
| Non-Fiction / Technical / Legal | `bạn` or `chúng ta` (reader-inclusive), `quý độc giả`, `tác giả`, impersonal/active phrasing | Keep consistent across the whole book; avoid shifting randomly between `bạn`, `các bạn`, and `quý vị`. |

### 1.3 Mid-Scene Shifts and Continuity

- Map every recurring speaker-addressee pair in the `Research_Dossier` Pronoun and Address Matrix before Phase 5 begins.
- A mid-scene pronoun shift (e.g., `tôi/anh` -> `em/anh` or `cậu/tớ` -> `mày/tao`) is valid **only** when triggered by an emotional rupture, confession, rank reversal, or reveal.
- Document intentional shifts in `Story_Bible` and `Chunk_Summary` so `continuity-reviewer` distinguishes deliberate narrative pivots from accidental drift.

---

## 2. Sino-Vietnamese (Hán-Việt) vs. Native Vietnamese (Thuần Việt) Balance

Vietnamese prose draws tonal weight from balancing two lexical strata:

- **Sino-Vietnamese (Hán-Việt)** — conveys formality, philosophical abstraction, legal authority, historical gravitas, and mythic scale (e.g., `công lý`, `giao ước`, `định mệnh`, `cổ vật`, `thẩm quyền`, `biên niên sử`).
- **Native Vietnamese (Thuần Việt)** — conveys sensory immediacy, physical action, emotional warmth, humor, and colloquial speech (e.g., `đau thương`, `run rẩy`, `nóng rực`, `giỡn mặt`, `chia tay`).

### Register Calibration Rules

1. Match the stratum to the narrator and speaker: an archaic chronicler or legal code leans Hán-Việt; a street urchin's dialogue leans Thuần Việt.
2. Avoid tonal whiplash within one sentence (for example, pairing high-court Hán-Việt phrasing with modern internet slang unless parody is intended).
3. Use `memory/glossary-vi.csv` for pre-solved canonical renderings of recurring literary, legal, psychological, and technical concepts.

---

## 3. Proper Noun and Special Term Policy

Follow the `Research_Dossier` classification (`official_published`, `community_established`, `partial`, or `none`):

1. **Retain Source Spelling**: Keep modern Western, Latin-script personal names, brands, and contemporary places in original form (`Sherlock Holmes`, `London`, `MIT`) when standard in modern Vietnamese publishing.
2. **Track A Canon First**: If an official or widely established Vietnamese translation exists, inherit its canonical personal names, toponyms, and signature terms unless `Translation_Brief` specifies a fresh re-translation.
3. **East Asian Classical / Historical Names**: Follow standard Hán-Việt reading for classical Chinese/historical names and titles when appropriate to the genre and target-market canon.
4. **Descriptive Epithets, Titles, and Organizations**: Translate meaningful titles, ranks, guilds, artifacts, and spells (`The High Council` -> `Hội đồng Tối cao` / approved canon) and lock them in `glossary.csv`.
5. **First-Mention Glosses**: When an opaque cultural term or neologism needs clarification and `Style_Sheet` allows notes, add a single concise inline parenthetical or `[ND: ...]` footnote on first mention only; never repeat glosses in later chunks.

---

## 4. Anti-Translatorese Forbidden Patterns

Check every chunk during Pass C (`chunk-translator`) and Peer Cross-Check (`continuity-reviewer`) to eliminate mechanical calques from English or other source languages:

| Forbidden Pattern | Why It Fails in Vietnamese | Preferred Natural Remedy |
|---|---|---|
| Mechanical passive `bị` / `được` | Overusing `bị` for neutral events or `được` for inanimate subjects (`cánh cửa được mở bởi anh ấy`) sounds robotic. | Use active voice (`anh mở cửa`) or natural Vietnamese topic-comment order (`cửa đã mở`). Reserve `bị` for adverse events (`bị thương`, `bị phạt`) and `được` for genuine benefit/receipt (`được khen`, `được trao`). |
| Mechanical `-ly` adverbial calques (`một cách ...`) | Strings like `anh nhìn cô một cách buồn bã` feel stiff and translated. | Use direct verb-adjective combinations or idiomatic adverbs (`anh buồn bã nhìn cô`, `anh nhìn cô đầy buồn bã`). |
| Abstract nominalization bloat (`sự ...`, `việc ...`, `tính ...`) | Literal noun chains (`việc thực hiện sự phát triển của ...`) weigh down prose. | Convert abstract nouns back into clear verbs and actors (`phát triển ...`, `khi họ thực hiện ...`). |
| Stiff relative-clause chains (`mà`, `cái mà`, `người mà`, `nơi mà`) | Chaining multiple `mà` clauses mirrors English `which/who/where` syntax awkwardly. | Split long sentences into natural sequential clauses or omit redundant `mà` connectors. |
| Redundant possessives (`của tôi`, `của anh ấy`, `của cô ấy`) | Translating every `his/her/my` (`anh ta đặt tay của anh ta lên vai của cô ta`) bloats dialogue and action. | Drop `của` when ownership is obvious from context (`anh đặt tay lên vai cô`). |
| Calqued copulas and tense markers (`là một`, `đã và đang`, `ở trong`) | Mechanical `đã và đang` or `là một người đàn ông cao lớn` reads like machine translation. | Use natural aspect markers (`vẫn đang`, `từng`) or drop redundant `một` before predicative adjectives/nouns (`anh cao lớn`). |

---

## 5. Vietnamese Book Typography and Dialogue Conventions

Record the chosen option in `style-sheet.md` and enforce it uniformly across all chunks (checked deterministically by `book_ops.py verify`):

1. **Dialogue Punctuation** (pick ONE convention per project, never mix across chunks):
   - *Traditional Vietnamese Book Style*: leading em-dash (`—`) at the start of each spoken turn on a new line; reporting tags separated by em-dash or comma.
   - *Modern Quoted Style*: curly double quotes (`“...”`) for spoken dialogue and single quotes (`‘...’`) for nested quotes.
2. **Numbers and Decimals**:
   - Standard Vietnamese prose/tables use dot `.` as thousands separator (`1.250.000`) and comma `,` as decimal separator (`3,14`), unless `Translation_Brief` preserves source technical/financial notation.
   - Never alter numbers inside code identifiers, URLs, semantic versions (`1.0.0`), or formal citations.
3. **Dates**:
   - Use `dd/mm/yyyy` for numeric dates and `ngày D tháng M năm YYYY` in narrative prose unless the source is an ISO technical specification.
4. **Structural Headings**:
   - Use consistent Vietnamese structural labels matching `memory/glossary-vi.csv` (`Lời mở đầu`, `Chương 1`, `Lời kết`, `Phụ lục`, `Mục lục`, `Chú thích cuối trang`).
5. **Code, URLs, and Formal Anchors**:
   - Preserve URLs, markdown anchors, table alignments, and code blocks verbatim.

---

## References

- Shared Vietnamese glossary memory: `memory/glossary-vi.csv`
- Two-tier glossary workflow: `memory/README.md`
- Research dossier schema: `core/schemas/research-dossier.md`
- Style sheet schema: `core/schemas/style-sheet.md`
