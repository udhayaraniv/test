#!/usr/bin/env bash
set -euo pipefail

PROJECT_CODE="${1:?Project code is required}"
ACTIVATE="${2:-false}"

WORK_DIR="./artifacts"
mkdir -p "${WORK_DIR}"

ARCHIVE_FILE="${WORK_DIR}/${PROJECT_CODE}.car"
IMPORT_RESPONSE_FILE="${WORK_DIR}/import_response.json"
EXPORT_RESPONSE_HEADERS="${WORK_DIR}/export_headers.txt"

echo "======================================"
echo "Starting OIC migration for ${PROJECT_CODE}"
echo "======================================"

required_vars=(
  SOURCE_BASE_URL
  TARGET_BASE_URL
  SOURCE_INSTANCE
  TARGET_INSTANCE
  SOURCE_TOKEN
  TARGET_TOKEN
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Missing required environment variable: ${var}"
    exit 1
  fi
done

echo "Checking source project exists..."
LIST_RESPONSE=$(curl -sS -X GET \
  -H "Authorization: Bearer ${SOURCE_TOKEN}" \
  -H "Accept: application/json" \
  "${SOURCE_BASE_URL}/ic/api/integration/v1/projects?integrationInstance=${SOURCE_INSTANCE}")

if ! echo "${LIST_RESPONSE}" | grep -q "\"code\"[[:space:]]*:[[:space:]]*\"${PROJECT_CODE}\""; then
  echo "Project ${PROJECT_CODE} not found in source instance ${SOURCE_INSTANCE}"
  echo "${LIST_RESPONSE}"
  exit 1
fi

echo "Exporting project from source..."
curl -sS -D "${EXPORT_RESPONSE_HEADERS}" \
  -X POST \
  -H "Authorization: Bearer ${SOURCE_TOKEN}" \
  -H "Content-Type: application/json" \
  -o "${ARCHIVE_FILE}" \
  "${SOURCE_BASE_URL}/ic/api/integration/v1/projects/${PROJECT_CODE}/archive?integrationInstance=${SOURCE_INSTANCE}" \
  -d "{
    \"name\": \"${PROJECT_CODE}\",
    \"code\": \"${PROJECT_CODE}\",
    \"type\": \"DEVELOPED\"
  }"

if [ ! -s "${ARCHIVE_FILE}" ]; then
  echo "Export failed: archive file is empty or missing"
  exit 1
fi

echo "Export successful: ${ARCHIVE_FILE}"
ls -lh "${ARCHIVE_FILE}"

echo "Importing project into target..."
HTTP_CODE=$(curl -sS \
  -o "${IMPORT_RESPONSE_FILE}" \
  -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${TARGET_TOKEN}" \
  -F "file=@${ARCHIVE_FILE}" \
  -F "type=application/octet-stream" \
  "${TARGET_BASE_URL}/ic/api/integration/v1/projects/archive?integrationInstance=${TARGET_INSTANCE}")

if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "201" ] || [ "${HTTP_CODE}" = "204" ]; then
  echo "Import successful with HTTP ${HTTP_CODE}"
elif [ "${HTTP_CODE}" = "409" ]; then
  echo "Import failed: project already exists in target"
  cat "${IMPORT_RESPONSE_FILE}"
  exit 1
else
  echo "Import failed with HTTP ${HTTP_CODE}"
  cat "${IMPORT_RESPONSE_FILE}"
  exit 1
fi

echo "Post-import note:"
echo "Configure target connections, lookups, certificates, and other dependencies before activation."

if [ "${ACTIVATE}" = "true" ]; then
  echo "Activation requested, but not implemented in this script."
  echo "Add activation only after dependency validation is complete."
fi

echo "======================================"
echo "Migration completed successfully"
echo "======================================"
