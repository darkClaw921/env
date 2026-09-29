#!/bin/sh
# Hourglyph hook for Claude Code — https://hourglyph.github.io/setup/
#
# Sends anonymous activity pings to the public peak-hours map:
#   session  — a new session started           (SessionStart)
#   message  — you sent a message to Claude    (UserPromptSubmit)
#   stop     — token counts of the last turn   (Stop)
#
# What leaves your machine: the event name and, for "stop", four integers
# (input / output / cache-write / cache-read tokens). Never prompts, answers,
# code, file paths, project names or session ids. The server adds the hour,
# weekday and country; it does not store your IP.
#
# Token counts are read locally from the transcript Claude Code passes to the
# hook. Requires only sh, awk and curl. Remove the hook entries from
# ~/.claude/settings.json to stop.

URL='https://ludtufvegukpzbdarhnq.supabase.co/rest/v1/rpc/track'
KEY='sb_publishable_yUz1zIFhM4V8qvELLDkKnA_YpjZmPIc'

post() {
  curl -s -m 5 -X POST "$URL" -H "apikey: $KEY" -H 'Content-Type: application/json' -d "$1" >/dev/null 2>&1
}

# Hook input JSON arrives on stdin. Keep it in memory only; for "message" it is
# never inspected (it contains your prompt).
input=$(cat)

case "$1" in
  session)
    post '{"p_event":"session"}'
    ;;
  message)
    post '{"p_event":"message"}'
    ;;
  stop)
    transcript=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\\\/\\/g')
    [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

    # Sum usage of assistant messages after the last real user prompt (tool results
    # and meta lines don't count as prompts). Streaming writes one message over
    # several lines, so dedupe by message id.
    tokens=$(tail -n 5000 "$transcript" | awk '
      function num(k,   s) {
        if (match($0, "\"" k "\":[ ]*[0-9]+")) { s = substr($0, RSTART, RLENGTH); sub(/.*:[ ]*/, "", s); return s + 0 }
        return 0
      }
      /"type":"user"/ && !/"tool_result"/ && !/"isMeta":true/ { last = NR }
      /"type":"assistant"/ && /"usage"/ {
        id = NR
        if (match($0, /"id":"msg_[A-Za-z0-9_]+"/)) id = substr($0, RSTART + 6, RLENGTH - 7)
        if (!(id in at)) at[id] = NR
        i[id] = num("input_tokens"); w[id] = num("cache_creation_input_tokens"); r[id] = num("cache_read_input_tokens")
        o0 = num("output_tokens"); if (o0 > o[id]) o[id] = o0
      }
      END {
        for (k in at) if (at[k] > last) { ti += i[k]; to += o[k]; tw += w[k]; tr += r[k] }
        printf "%d %d %d %d", ti, to, tw, tr
      }')
    set -- $tokens
    [ "${1:-0}${2:-0}${3:-0}${4:-0}" = "0000" ] && exit 0
    post "{\"p_event\":\"tokens\",\"p_input\":${1:-0},\"p_output\":${2:-0},\"p_cache_write\":${3:-0},\"p_cache_read\":${4:-0}}"
    ;;
esac
exit 0
