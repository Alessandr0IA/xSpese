#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-${PROJECT_ROOT}/xSpese.xcodeproj}"
SCHEME="${SCHEME:-xSpese}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-xSpese}"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-${PROJECT_ROOT}/build/ipa-derived-data}"

fail() {
    echo "Errore: $*" >&2
    exit 1
}

require_project_subdirectory() {
    local path="$1"
    case "${path}" in
        "${PROJECT_ROOT}"/*) ;;
        *) fail "il percorso deve essere interno al progetto: ${path}" ;;
    esac
    [[ "${path}" != "${PROJECT_ROOT}" ]] || fail "rifiutata operazione sulla radice del progetto"
}

command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild non è disponibile"
command -v python3 >/dev/null 2>&1 || fail "python3 non è disponibile"
command -v zip >/dev/null 2>&1 || fail "zip non è disponibile"
[[ -d "${PROJECT_PATH}" ]] || fail "progetto Xcode non trovato: ${PROJECT_PATH}"

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

require_project_subdirectory "${DIST_DIR}"
require_project_subdirectory "${DERIVED_DATA_DIR}"

rm -rf "${DIST_DIR}" "${DERIVED_DATA_DIR}"
mkdir -p "${DIST_DIR}" "${DERIVED_DATA_DIR}"

echo "Build unsigned di ${APP_NAME} (${CONFIGURATION})…"
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    clean build

APP_PATH="${DERIVED_DATA_DIR}/Build/Products/${CONFIGURATION}-iphoneos/${APP_NAME}.app"
INFO_PLIST="${APP_PATH}/Info.plist"
[[ -d "${APP_PATH}" ]] || fail "bundle .app non trovato: ${APP_PATH}"
[[ -f "${INFO_PLIST}" ]] || fail "Info.plist compilato non trovato"
[[ -f "${APP_PATH}/${APP_NAME}" ]] || fail "eseguibile principale non trovato"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] || \
    fail "MARKETING_VERSION non è semantic versioning: ${VERSION}"

if [[ -n "${EXPECTED_VERSION:-}" && "${VERSION}" != "${EXPECTED_VERSION}" ]]; then
    fail "il tag richiede ${EXPECTED_VERSION}, ma Xcode dichiara ${VERSION}"
fi

PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xspese-ipa.XXXXXX")"
trap 'rm -rf "${PACKAGE_DIR}"' EXIT
mkdir -p "${PACKAGE_DIR}/Payload"
/usr/bin/ditto "${APP_PATH}" "${PACKAGE_DIR}/Payload/${APP_NAME}.app"

IPA_NAME="${APP_NAME}-${VERSION}.ipa"
IPA_PATH="${DIST_DIR}/${IPA_NAME}"
(
    cd "${PACKAGE_DIR}"
    /usr/bin/zip -qry -y "${IPA_PATH}" Payload
)

[[ -s "${IPA_PATH}" ]] || fail "IPA non creato"
/usr/bin/unzip -tq "${IPA_PATH}" >/dev/null || fail "l'IPA non è uno ZIP valido"
/usr/bin/unzip -l "${IPA_PATH}" | grep -q "Payload/${APP_NAME}.app/Info.plist" || \
    fail "l'IPA non contiene Payload/${APP_NAME}.app/Info.plist"

python3 - "${IPA_PATH}" "${DIST_DIR}/build-info.json" "${APP_NAME}" "${VERSION}" "${BUILD_NUMBER}" "${BUNDLE_IDENTIFIER}" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

ipa_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
payload = {
    "name": sys.argv[3],
    "version": sys.argv[4],
    "build": sys.argv[5],
    "bundleIdentifier": sys.argv[6],
    "ipa": ipa_path.name,
    "size": ipa_path.stat().st_size,
    "sha256": hashlib.sha256(ipa_path.read_bytes()).hexdigest(),
    "signed": False,
}
output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

echo "IPA creato: ${IPA_PATH}"
echo "Metadati: ${DIST_DIR}/build-info.json"
echo "Nota: l'IPA è unsigned e deve essere firmato dal metodo di installazione."
