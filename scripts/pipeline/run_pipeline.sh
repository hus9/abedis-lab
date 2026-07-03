#!/bin/bash
# Lit Bulb Lab — nightly publishing pipeline orchestrator
# Usage:
#   ./run_pipeline.sh                    -> pulls next "pending" topic from content-calendar.yaml
#   TEST_TOPIC="Some Topic" TEST_CATEGORY="AI" TEST_SLUG="some-topic-test" ./run_pipeline.sh
#       -> runs a one-off test topic, does NOT touch git or content-calendar.yaml

set -uo pipefail

# launchd agents get a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin) — needed
# to find `claude` and `yq` (brew's yq, not the system python3's yaml module,
# which launchd's python3 resolution doesn't have)
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPE_DIR="$REPO_DIR/scripts/pipeline"
STATE_DIR="$PIPE_DIR/state"
STAGES_DIR="$PIPE_DIR/stages"
LOG_DIR="$PIPE_DIR/logs"
CALENDAR="$REPO_DIR/content-calendar.yaml"
SETTINGS="$PIPE_DIR/pipeline-settings.json"

DATE="$(date +%F)"

# ---- Resolve today's topic ----
if [[ -n "${TEST_TOPIC:-}" ]]; then
  TOPIC="$TEST_TOPIC"
  CATEGORY="${TEST_CATEGORY:-Test}"
  SLUG="${TEST_SLUG:-test-topic}"
  IS_TEST=1
  # Namespace all state/logs so a test never collides with (or is blocked by)
  # the same calendar day's real run.
  DATE="$DATE-test"
else
  IS_TEST=0
fi

RUN_LOG="$LOG_DIR/$DATE.log"
mkdir -p "$STATE_DIR" "$LOG_DIR"
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$RUN_LOG"; }

if [[ "$IS_TEST" == "1" ]]; then
  touch "$STATE_DIR/$DATE-TEST_MODE"
  log "TEST MODE — topic='$TOPIC' category='$CATEGORY' slug='$SLUG' (calendar untouched, no git push)"
else
  # ---- Already-done guard (prevents double runs, e.g. after a late wake) ----
  if [[ -f "$STATE_DIR/$DATE-SUCCESS.md" ]]; then
    log "Today's post already published successfully. Exiting."
    exit 0
  fi

  # Pull first entry with status: pending (yq preferred; python fallback).
  # Tab separators: topic may contain spaces, space-IFS read garbles it.
  if command -v yq >/dev/null 2>&1; then
    IFS=$'\t' read -r TOPIC CATEGORY SLUG < <(
      yq e -o=tsv '[.[] | select(.status == "pending")] | .[0] | [.topic, .category, .slug]' "$CALENDAR"
    )
  else
    IFS=$'\t' read -r TOPIC CATEGORY SLUG < <(python3 - "$CALENDAR" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
for e in data:
    if e.get("status") == "pending":
        print(f"{e['topic']}\t{e['category']}\t{e['slug']}")
        break
PY
)
  fi

  if [[ -z "${TOPIC:-}" || "$TOPIC" == "null" ]]; then
    log "No pending topics left in content-calendar.yaml. Nothing to publish."
    exit 0
  fi
  log "Today's topic: '$TOPIC' (category: $CATEGORY, slug: $SLUG)"
fi

export DATE TOPIC CATEGORY SLUG

# ---- Render a stage prompt: unattended header + template, with variables ----
render_stage() {
  local stage="$1" out="$2"
  cat "$STAGES_DIR/_unattended.md" "$STAGES_DIR/$stage.md" | sed \
    -e "s|{{date}}|$DATE|g" \
    -e "s|{{topic}}|$TOPIC|g" \
    -e "s|{{category}}|$CATEGORY|g" \
    -e "s|{{slug}}|$SLUG|g" \
    -e "s|{{stage}}|$stage|g" \
    > "$out"
}

# ---- Run a single stage via Claude Code CLI ----
# Success is judged ONLY by verify_cmd (claude -p exits 0 on any completed
# turn, no matter what the agent says). Every stage has one.
# On a retry, the previous attempt's output is appended to the prompt so the
# model can see what went wrong instead of repeating it.
RATE_LIMIT_FILE="$STATE_DIR/$DATE-ratelimit-reset"
API_ERROR_FILE="$STATE_DIR/$DATE-api-error"

run_stage_once() {
  local stage="$1"
  local verify_cmd="$2"
  local model="$3"
  local rendered="$STATE_DIR/$DATE-$stage-prompt.md"
  local checkpoint="$STATE_DIR/$DATE-$stage.done"
  local stage_output="$STATE_DIR/$DATE-$stage-output.log"
  local blocked="$STATE_DIR/$DATE-$stage-blocked.md"

  if [[ -f "$checkpoint" ]]; then
    log "Stage '$stage' already complete (checkpoint found). Skipping."
    return 0
  fi

  render_stage "$stage" "$rendered"

  # Feed the previous failed attempt back so the retry is informed, not blind.
  if [[ -s "$stage_output" ]]; then
    {
      echo ""
      echo "---"
      echo "## PREVIOUS ATTEMPT FAILED"
      echo "Your prior run of this stage ended without producing the required output files. Its final output was:"
      echo '```'
      tail -40 "$stage_output"
      echo '```'
      echo "Do not repeat that mistake. Produce the output files this time."
    } >> "$rendered"
  fi

  log "Running stage: $stage (model: $model)"

  # --settings: hooks disabled for unattended runs
  # --strict-mcp-config + empty config: user's MCP servers (Gmail/Drive/
  # browser/etc.) don't load into pipeline sessions -- less cost, less noise
  if claude -p "$(cat "$rendered")" \
      --model "$model" \
      --dangerously-skip-permissions \
      --settings "$SETTINGS" \
      --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
      > "$stage_output" 2>&1; then
    cat "$stage_output" >> "$RUN_LOG"
    if ! eval "$verify_cmd"; then
      log "Stage '$stage' finished but verification failed -- treating as FAILED."
      [[ -f "$blocked" ]] && log "Stage left a blocked-note: $(head -3 "$blocked")"
      return 1
    fi
    touch "$checkpoint"
    log "Stage '$stage' succeeded."
    return 0
  else
    cat "$stage_output" >> "$RUN_LOG"
    log "Stage '$stage' FAILED (non-zero exit)."
    local reset
    reset=$(grep -oE 'resets [0-9]{1,2}:[0-9]{2}(am|pm)' "$stage_output" | head -1)
    if [[ -n "$reset" ]]; then
      echo "$reset" > "$RATE_LIMIT_FILE"
      log "Failure was a session rate limit ($reset) -- not a stage bug."
    elif grep -qE 'API Error|Connection closed|ECONNRESET|ETIMEDOUT|fetch failed' "$stage_output"; then
      touch "$API_ERROR_FILE"
      log "Failure was a transport/API error -- not a stage bug."
    fi
    return 1
  fi
}

# ---- Rasterize the Instagram slides (Instagram only accepts PNG/JPEG) ----
convert_instagram_slides() {
  local slide_dir="$HOME/Desktop/litbulb-instagram/$DATE-$SLUG"
  if [[ ! -d "$slide_dir" ]] || ! ls "$slide_dir"/*.svg >/dev/null 2>&1; then
    return 0
  fi
  log "Converting Instagram slides in $slide_dir to PNG..."
  if (cd "$REPO_DIR" && node scripts/pipeline/svg-to-png.mjs "$slide_dir") >> "$RUN_LOG" 2>&1; then
    log "SVG->PNG conversion succeeded."
  else
    log "SVG->PNG conversion FAILED -- slides left as SVG, needs manual conversion."
  fi
}

# ---- Sleep until the account's rate-limit reset time (+5min buffer) ----
sleep_until_reset() {
  local time_str target_epoch now_epoch today tomorrow
  time_str=$(grep -oE '[0-9]{1,2}:[0-9]{2}(am|pm)' <<< "$1" | head -1 | tr '[:lower:]' '[:upper:]')
  now_epoch=$(date +%s)
  today="$(date +%Y-%m-%d)"
  target_epoch=$(date -j -f "%Y-%m-%d %I:%M%p" "$today $time_str" "+%s" 2>/dev/null)
  if [[ -z "$target_epoch" || "$target_epoch" -le "$now_epoch" ]]; then
    tomorrow="$(date -v+1d +%Y-%m-%d)"
    target_epoch=$(date -j -f "%Y-%m-%d %I:%M%p" "$tomorrow $time_str" "+%s" 2>/dev/null)
  fi
  if [[ -z "$target_epoch" ]]; then
    log "Couldn't parse reset time '$1' -- falling back to 1hr wait."
    sleep 3600
    return
  fi
  local wait_secs=$(( target_epoch - now_epoch + 300 ))
  (( wait_secs < 60 )) && wait_secs=300
  log "Rate-limited until ~$1 -- sleeping $(( wait_secs / 60 )) min instead of retrying blind."
  sleep "$wait_secs"
}

# ---- Stage table: name -> verify condition + model ----
# Cheap/mechanical git plumbing runs on haiku; everything needing judgment
# or design runs on sonnet (haiku repeatedly stalled on the illustrator).
STAGES=(01-researcher 02-writer 03-illustrator 04-editor 05-publisher)

stage_verify() {
  case "$1" in
    01-researcher) echo "[[ -f '$STATE_DIR/$DATE-research.md' ]]" ;;
    02-writer)     echo "[[ -f '$REPO_DIR/src/content/posts/$SLUG.mdx' ]] && ! grep -q '<!--' '$REPO_DIR/src/content/posts/$SLUG.mdx'" ;;
    03-illustrator) echo "! grep -q 'IMAGE:' '$REPO_DIR/src/content/posts/$SLUG.mdx' && ls '$REPO_DIR/src/assets/posts/$SLUG/'*.svg >/dev/null 2>&1 && [[ \$(ls \"\$HOME/Desktop/litbulb-instagram/$DATE-$SLUG\"/instagram-slide-*.svg 2>/dev/null | wc -l) -ge 5 ]]" ;;
    04-editor)     echo "[[ -f '$STATE_DIR/$DATE-04-editor-pass.md' && ! -f '$STATE_DIR/$DATE-editor-flags.md' ]]" ;;
    05-publisher)  echo "[[ -f '$STATE_DIR/$DATE-SUCCESS.md' ]]" ;;
  esac
}

stage_model() {
  case "$1" in
    05-publisher) echo "haiku" ;;
    *)            echo "sonnet" ;;
  esac
}

run_full_pipeline() {
  for stage in "${STAGES[@]}"; do
    if ! run_stage_once "$stage" "$(stage_verify "$stage")" "$(stage_model "$stage")"; then
      FAILED_STAGE="$stage"
      return 1
    fi
    [[ "$stage" == "03-illustrator" ]] && convert_instagram_slides
  done
  return 0
}

fail_terminal() {
  local reason="$1"
  log "### PIPELINE FAILED — $reason ###"
  {
    echo "# Pipeline failed — $DATE"
    echo
    echo "Topic: $TOPIC ($CATEGORY)"
    echo "Reason: $reason"
    echo "Test run: $IS_TEST"
    echo
    echo "## Last log lines"
    echo '```'
    tail -60 "$RUN_LOG"
    echo '```'
    if [[ "$IS_TEST" == "0" ]]; then
      echo
      echo "Topic remains \"pending\" in content-calendar.yaml. Tomorrow's run"
      echo "proceeds normally with this same topic first in the queue."
    fi
  } > "$STATE_DIR/$DATE-FAILED.md"
  notify "Lit Bulb Lab ✗" "Pipeline failed — $reason"
  exit 1
}

# ---- Main loop: failures are classified, not treated uniformly ----
# - editor content flag  -> terminal BLOCKED (a retry cannot verify a fact)
# - session rate limit   -> sleep until reset, retry (does not consume a
#                           stall retry; capped at 2 sleeps)
# - anything else        -> ONE informed retry of the failed stage (prompt
#                           gets the previous output appended). Completed
#                           stages are never wiped: re-running research from
#                           scratch is how a hallucination got in last time.
STALL_RETRIES=0
RATE_SLEEPS=0
API_RETRIES=0
FAILED_STAGE=""

while true; do
  if run_full_pipeline; then
    log "Pipeline completed successfully."
    notify "Lit Bulb Lab ✓" "Published: $TOPIC"
    exit 0
  fi

  if [[ -f "$STATE_DIR/$DATE-editor-flags.md" ]]; then
    fail_terminal "editor blocked publication (see $DATE-editor-flags.md) — needs human review"
  fi

  if [[ -f "$RATE_LIMIT_FILE" ]]; then
    if (( RATE_SLEEPS >= 2 )); then
      fail_terminal "hit session rate limit ${RATE_SLEEPS}+ times"
    fi
    RATE_SLEEPS=$(( RATE_SLEEPS + 1 ))
    sleep_until_reset "$(cat "$RATE_LIMIT_FILE")"
    rm -f "$RATE_LIMIT_FILE"
    continue
  fi

  # Transient transport errors (connection dropped mid-response, timeouts):
  # short backoff, doesn't consume the stall retry. Observed in the wild on
  # the 2026-07-03 validation run.
  if [[ -f "$API_ERROR_FILE" ]]; then
    if (( API_RETRIES >= 3 )); then
      fail_terminal "repeated API/transport errors (${API_RETRIES} retries)"
    fi
    API_RETRIES=$(( API_RETRIES + 1 ))
    rm -f "$API_ERROR_FILE"
    log "Transport error -- backing off $(( API_RETRIES * 120 ))s before retrying (attempt $API_RETRIES/3)."
    sleep $(( API_RETRIES * 120 ))
    continue
  fi

  if (( STALL_RETRIES >= 1 )); then
    fail_terminal "stage '$FAILED_STAGE' failed twice (second attempt had the first failure's output in its prompt)"
  fi
  STALL_RETRIES=$(( STALL_RETRIES + 1 ))
  log "Stage '$FAILED_STAGE' stalled. Retrying it once with the failure context in the prompt."
done
