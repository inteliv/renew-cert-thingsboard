#!/bin/bash
# /usr/local/bin/haproxy-refresh-notify.sh

WEBHOOK_URL="https://hooks.slack.com/services/XXX/YYY/ZZZ"
DOMAIN="iot.inteliv.net"
HOSTNAME=$(hostname)
NOW=$(date '+%Y-%m-%d %H:%M:%S')
LOG_FILE="/var/log/haproxy-certbot.log"
TMP_LOG="/tmp/certbot-renew-$$.log"

# A feature that sends a colored notification to Slack
send_slack_notification() {
  local status="$1"
  local color="$2"
  local message="Let's Encrypt certificate renewal *$status* on \`$HOSTNAME\` at \`$NOW\`."

  curl -s -X POST -H 'Content-type: application/json' --data "{
    \"attachments\": [{
      \"fallback\": \"$message\",
      \"color\": \"$color\",
      \"text\": \"$message\"
    }]
  }" "$WEBHOOK_URL" > /dev/null
}

NOW=$(date '+%Y-%m-%d %H:%M:%S')
echo "=== [$NOW] Starting certificate renewal ===" >> "$LOG_FILE"

# Run certbot and save the log to a temporary file
/usr/bin/certbot -c /usr/local/etc/letsencrypt/cli.ini -q renew > "$TMP_LOG" 2>&1
CERTBOT_EXIT_CODE=$?
cat "$TMP_LOG" >> "$LOG_FILE"

# Certbot error handling
if [ $CERTBOT_EXIT_CODE -ne 0 ]; then
  echo "!!! [$NOW] Renewal failed with exit code $CERTBOT_EXIT_CODE ===" >> "$LOG_FILE"
  send_slack_notification "FAILED (exit $CERTBOT_EXIT_CODE)" "danger"
  rm -f "$TMP_LOG"
  exit 1
fi

# If the certificate has actually been renewed
if grep -q -E "Cert is due for renewal|Congratulations, all renewals succeeded" "$TMP_LOG"; then
  echo "[$NOW] Certificate renewed. Reloading HAProxy..." >> "$LOG_FILE"

  /bin/systemctl reload haproxy
  if [ $? -eq 0 ]; then
    echo "[$NOW] HAProxy reloaded successfully." >> "$LOG_FILE"
    send_slack_notification "SUCCEEDED – certificate renewed and HAProxy reloaded" "good"
  else
    echo "[$NOW] ❌ Failed to reload HAProxy!" >> "$LOG_FILE"
    send_slack_notification "FAILED – certificate renewed but HAProxy reload failed" "danger"
  fi

else
  echo "=== [$NOW] No renewal needed – no notification sent ===" >> "$LOG_FILE"
fi

rm -f "$TMP_LOG"
