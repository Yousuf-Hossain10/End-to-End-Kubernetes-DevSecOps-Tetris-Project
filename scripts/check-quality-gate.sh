#!/usr/bin/env bash
#
# Polls the local SonarQube server for the quality gate result of the
# analysis that was just run in $SCAN_DIR, and prints PASS/FAIL.
#
# This is the manual equivalent of Jenkins' `waitForQualityGate` step.
# Like the original Jenkinsfiles (abortPipeline: false), a failed gate
# is reported but does NOT fail the workflow — it's informational.
#
# Required env vars:
#   SONAR_HOST_URL   e.g. http://localhost:9000
#   SONAR_TOKEN      token generated in SonarQube UI, stored as a repo secret
# Optional:
#   SCAN_DIR         directory the scanner ran in (default: current dir)

set -euo pipefail

SCAN_DIR="${SCAN_DIR:-.}"
REPORT_FILE="${SCAN_DIR}/.scannerwork/report-task.txt"

if [[ ! -f "${REPORT_FILE}" ]]; then
  echo "No report-task.txt found at ${REPORT_FILE} — did the sonar-scanner step run first?"
  exit 1
fi

CE_TASK_ID="$(grep '^ceTaskId=' "${REPORT_FILE}" | cut -d= -f2-)"
if [[ -z "${CE_TASK_ID}" ]]; then
  echo "Could not find ceTaskId in ${REPORT_FILE}"
  exit 1
fi

echo "Waiting on SonarQube background task ${CE_TASK_ID}..."

STATUS="PENDING"
ANALYSIS_ID=""
for _ in $(seq 1 30); do
  RESPONSE="$(curl -sf -u "${SONAR_TOKEN}:" "${SONAR_HOST_URL}/api/ce/task?id=${CE_TASK_ID}")"
  STATUS="$(echo "${RESPONSE}" | grep -o '"status":"[A-Z]*"' | head -1 | cut -d'"' -f4)"

  if [[ "${STATUS}" == "SUCCESS" ]]; then
    ANALYSIS_ID="$(echo "${RESPONSE}" | grep -o '"analysisId":"[^"]*"' | head -1 | cut -d'"' -f4)"
    break
  elif [[ "${STATUS}" == "FAILED" || "${STATUS}" == "CANCELED" ]]; then
    echo "SonarQube background task ended with status ${STATUS}"
    exit 0
  fi
  sleep 2
done

if [[ -z "${ANALYSIS_ID}" ]]; then
  echo "Timed out waiting for SonarQube analysis to finish (last status: ${STATUS})"
  exit 0
fi

GATE_RESPONSE="$(curl -sf -u "${SONAR_TOKEN}:" "${SONAR_HOST_URL}/api/qualitygates/project_status?analysisId=${ANALYSIS_ID}")"
GATE_STATUS="$(echo "${GATE_RESPONSE}" | grep -o '"status":"[A-Z]*"' | head -1 | cut -d'"' -f4)"

echo "=================================================="
echo " SonarQube Quality Gate: ${GATE_STATUS}"
echo "=================================================="

if [[ "${GATE_STATUS}" != "OK" ]]; then
  echo "Quality gate did not pass — continuing anyway (non-blocking, matches Jenkins abortPipeline:false)."
fi

exit 0
