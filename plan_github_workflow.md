# GitHub Workflow - Automatic Binary Export Plan

## Goal

Add a GitHub Actions workflow that automatically builds the AutoLocation macOS app and publishes it as a downloadable artifact (and optionally as a GitHub Release).

---

## Context

- **Project type**: macOS SwiftUI app (macOS 14.0+, Xcode 16+, Swift 5.9)
- **Build system**: XcodeGen (`project.yml`) generates the `.xcodeproj`
- **Python bridge**: `bridge.py` bundled via PyInstaller into `Scripts/dist/bridge/bridge`
- **Code signing**: Ad-hoc (`CODE_SIGN_IDENTITY: "-"`) - no Apple Developer certificate required
- **Output**: `AutoLocation.app` bundle (macOS .app), packaged as `.zip` or `.dmg`

---

## Actions

### 1. Create workflow file

- **File**: `.github/workflows/build-and-release.yml`
- **Runner**: `macos-15` (latest macOS runner with Xcode 16+)

### 2. Workflow triggers

| Trigger | Purpose |
|---|---|
| `push` tags `v*` (e.g. `v1.0.0`) | Automatic release on version tag |
| `workflow_dispatch` | Manual trigger for ad-hoc builds |

### 3. Workflow steps

```
Step 1: Checkout code
Step 2: Setup Python 3.13
Step 3: Setup Python venv & install pymobiledevice3 + pyinstaller
Step 4: Build the Python bridge binary (Scripts/build_bridge.sh)
Step 5: Install XcodeGen (brew install xcodegen)
Step 6: Generate Xcode project (xcodegen generate)
Step 7: Build the app (xcodebuild archive)
Step 8: Export .app from archive
Step 9: Package into .zip
Step 10: Upload artifact (actions/upload-artifact)
Step 11: Create GitHub Release & attach .zip (only on tag push)
```

### 4. Detailed step breakdown

#### Step 2-4: Python bridge build
```bash
cd Scripts
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install pymobiledevice3 pyinstaller
./build_bridge.sh
```

#### Step 5-6: Project generation
```bash
brew install xcodegen
xcodegen generate
```

#### Step 7-8: Xcode build & archive
```bash
xcodebuild archive \
  -scheme AutoLocation \
  -configuration Release \
  -archivePath build/AutoLocation.xcarchive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO

# Copy .app from archive
cp -R build/AutoLocation.xcarchive/Products/Applications/AutoLocation.app build/AutoLocation.app
```

#### Step 9: Package
```bash
cd build
zip -r -y AutoLocation-macos.zip AutoLocation.app
```

#### Step 10-11: Upload & Release
- Use `actions/upload-artifact@v4` for every build
- Use `softprops/action-gh-release@v2` to create a GitHub Release with the `.zip` attached (only on `v*` tags)

### 5. Files to create

| File | Action |
|---|---|
| `.github/workflows/build-and-release.yml` | Create - main workflow |

### 6. Considerations

- **No Developer ID signing**: Since the project uses ad-hoc signing, users will need to right-click > Open on first launch (Gatekeeper bypass). This is acceptable for open-source distribution.
- **Bridge binary size**: The PyInstaller `--onedir` output can be large (~100-200MB). The `.zip` artifact will reflect this.
- **Caching**: Can add `actions/cache` for Homebrew (xcodegen) and pip dependencies to speed up repeat builds. Not critical for v1.
- **Xcode version pinning**: Use `maxim-lobanov/setup-xcode@v1` if a specific Xcode version is needed on the runner.

---

## Execution order

1. [x] Research project structure and build process
2. [x] Create `.github/workflows/build-and-release.yml`
3. [ ] Test workflow (push a tag or trigger manually)
