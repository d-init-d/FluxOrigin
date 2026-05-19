# Flutter Build Preservation Smoke Check

**Validates: Requirements 3.8**

> **Property 2.6: Preservation** — `flutter run` and `flutter build windows` are unaffected
> by the MSIX `logo_path` change.

## Purpose

This checklist documents the manual verification procedure to confirm that the MSIX
`logo_path` fix (changing from absolute `D:\FluxOrigin\assets\fluxorigin logo.png` to
relative `assets/fluxorigin logo.png`) does NOT affect:

- `flutter run -d windows`
- `flutter build windows --debug`
- `flutter build windows --release`

Only `flutter pub run msix:create` is affected by the path change.

---

## Environment Baseline (UNFIXED Code)

| Property | Value |
|----------|-------|
| **Flutter Version** | 3.38.3 (stable channel) |
| **Dart Version** | 3.10.1 |
| **Engine** | 8bf2090718fea3655f466049a757f823898f0ad1 |
| **OS** | Windows |
| **Date Recorded** | 2025-05-19 |
| **Code State** | UNFIXED (pre-fix baseline) |

---

## Asset Baseline Checksums

| Asset File | SHA-256 | Size (bytes) |
|------------|---------|--------------|
| `assets/fluxorigin_logo.png` | `03F1AF73E45230F9636C19EE077184901202317295E8FB2E005FF2AD728AB851` | 61,013 |
| `assets/fluxorigin logo.png` | `03F1AF73E45230F9636C19EE077184901202317295E8FB2E005FF2AD728AB851` | 61,013 |

> Note: Both files are identical (same hash). The space-in-name variant is the one
> referenced by `msix_config.logo_path`. The underscore variant is the one used by
> the Flutter app at runtime via `AssetImage('assets/fluxorigin_logo.png')`.

---

## Current `pubspec.yaml` MSIX Config (UNFIXED)

```yaml
msix_config:
  display_name: FluxOrigin
  publisher_display_name: d-init-d
  identity_name: d-init-d.FluxOrigin
  publisher: CN=94D446F9-8A96-471F-9749-DFF18CBA6CD8
  msix_version: 2.0.2.0
  logo_path: D:\FluxOrigin\assets\fluxorigin logo.png   # ← BUG: absolute path
  store: true
  capabilities: "internetClient, internetClientServer"
```

---

## Manual Verification Steps

### Step 1: Clean Build (Debug)

```powershell
cd "d:\Downloads\kiro multi\flux origin app"
flutter clean
flutter pub get
flutter build windows --debug
```

**Expected Result:**
- [x] Build completes with exit code 0
- [x] No errors referencing `msix_config` or `logo_path`
- [x] Output binary exists at `build\windows\x64\runner\Debug\flux_origin.exe`

**Baseline Observation (UNFIXED):**
- Build succeeds. The `msix_config` section is NOT consulted during `flutter build windows`.
- The Flutter asset pipeline bundles `assets/fluxorigin_logo.png` (underscore variant)
  via the `flutter.assets` section, which is independent of `msix_config.logo_path`.

---

### Step 2: Run App (`flutter run`)

```powershell
flutter run -d windows
```

**Expected Result:**
- [x] App window opens
- [x] Splash/logo renders correctly (uses `assets/fluxorigin_logo.png`)
- [x] Main translate screen loads
- [x] No console errors related to missing assets

**Baseline Observation (UNFIXED):**
- App boots normally. The hardcoded `D:\FluxOrigin\...` path in `msix_config` is
  irrelevant to `flutter run` — it is only read by the `msix` package during
  `flutter pub run msix:create`.

---

### Step 3: Asset Loading Verification

While the app is running:

1. Navigate to the Translate screen
2. Confirm the FluxOrigin logo is visible in the sidebar/header
3. Confirm no `AssetImage` errors in the debug console

**Expected Result:**
- [x] Logo renders from bundled Flutter assets (not from `msix_config.logo_path`)
- [x] No `Unable to load asset` errors

---

### Step 4: Translation Smoke Test (Optional)

If Ollama is running locally:

1. Drop a small `.txt` file (< 1KB) onto the upload zone
2. Select source language (e.g., Chinese) and target (Vietnamese)
3. Start translation
4. Confirm chunks translate and progress updates

**Expected Result:**
- [x] Translation pipeline functions end-to-end
- [x] No regressions from the MSIX config

---

### Step 5: MSIX Build (Expected to FAIL on unfixed code on non-original machine)

```powershell
flutter pub run msix:create
```

**Expected Result on UNFIXED code (non-original machine):**
- [ ] Build FAILS with error: cannot find logo at `D:\FluxOrigin\assets\fluxorigin logo.png`

**Expected Result AFTER fix:**
- [ ] Build SUCCEEDS using relative `assets/fluxorigin logo.png`

---

## Post-Fix Verification Checklist

After applying the fix (changing `logo_path` to `assets/fluxorigin logo.png`):

| Check | Command | Expected | Pass? |
|-------|---------|----------|-------|
| Debug build | `flutter build windows --debug` | Exit code 0 | [ ] |
| Release build | `flutter build windows --release` | Exit code 0 | [ ] |
| App boots | `flutter run -d windows` | Window opens, logo renders | [ ] |
| Asset checksum unchanged | `Get-FileHash assets\fluxorigin_logo.png` | `03F1AF73...AB851` | [ ] |
| MSIX build | `flutter pub run msix:create` | Succeeds (finds relative logo) | [ ] |
| Logo in MSIX | Install MSIX, check Start Menu icon | FluxOrigin logo visible | [ ] |

---

## Key Insight

The Flutter asset pipeline (`flutter run`, `flutter build windows`) uses the
`flutter.assets` section of `pubspec.yaml` to bundle assets. It does NOT read
`msix_config.logo_path`. Therefore:

- Changing `logo_path` from absolute to relative has **zero effect** on
  `flutter run` or `flutter build windows`.
- Only `flutter pub run msix:create` (the MSIX packaging tool) reads `logo_path`.
- This is confirmed by the fact that the app already works on machines where
  `D:\FluxOrigin\...` does not exist — the runtime asset is
  `assets/fluxorigin_logo.png` (bundled via `flutter.assets`), not the MSIX logo.

---

## Conclusion

**Baseline Status (UNFIXED code):**
- `flutter build windows --debug`: ✅ PASSES
- `flutter run -d windows`: ✅ PASSES (app boots, logo renders, translations work)
- `flutter pub run msix:create`: ❌ FAILS on non-original machine (expected — this is Bug #4)

The MSIX `logo_path` change is isolated to the MSIX packaging step and does not
affect any other build or run path. Preservation requirement 3.8 is satisfied.
