#!/usr/bin/env bash
# Installs the app on an Android emulator and tries real downloads through it.
# Used by the "Test on a phone" workflow. Prints a summary; fails only if the built-in helpers don't run.
set -u
APK=$1; PKG=com.vidgrab.app; PORT=8765; H="http://127.0.0.1:$PORT"
adb install -r -g "$APK" || exit 1
adb shell am start -n $PKG/.MainActivity
adb forward tcp:$PORT tcp:$PORT
for i in $(seq 1 150); do curl -sf "$H/api/health" >/dev/null && break; sleep 2; done
if ! curl -sf "$H/api/health" >/dev/null; then
  echo "::error::the app did not start"; adb logcat -d | grep -E "AndroidRuntime|python|chaquopy|FATAL|vidgrab" | tail -n 150; exit 1
fi
echo "== health";   curl -s "$H/api/health"; echo
echo "== selftest"; ST=$(curl -s "$H/api/selftest"); echo "$ST"
echo "== engine";   curl -s "$H/api/engine"; echo

try() {   # try <name> <json body>
  local name=$1 body=$2 id st
  id=$(curl -s -H 'Content-Type: application/json' -d "$body" "$H/api/download" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))')
  for i in $(seq 1 120); do
    st=$(curl -s "$H/api/status/$id")
    case $(echo "$st" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status"))') in done|error|cancelled) break;; esac
    sleep 3
  done
  echo "$st" | python3 -c "import sys,json;d=json.load(sys.stdin);print(f'{\"OK  \" if d.get(\"status\")==\"done\" else \"FAIL\"} $name: {d.get(\"status\")} | {d.get(\"title\")} | {d.get(\"name\")} | {d.get(\"size\")} | {d.get(\"error\")}')" | tee -a results.txt
}
: > results.txt
try "YouTube video 720p"   '{"url":"https://www.youtube.com/watch?v=jNQXAC9IVRw","kind":"video","quality":"720"}'
try "YouTube MP3"          '{"url":"https://www.youtube.com/watch?v=jNQXAC9IVRw","kind":"audio","audio":"mp3","abr":"128"}'
try "YouTube HD (1080p)"   '{"url":"https://www.youtube.com/watch?v=aqz-KE-bpKQ","kind":"video","quality":"1080","start":"0:10","end":"0:20"}'
try "Direct MP4 link"      '{"url":"https://download.samplelib.com/mp4/sample-5s.mp4","kind":"video","quality":"720"}'
try "Vimeo"                '{"url":"https://vimeo.com/76979871","kind":"video","quality":"720"}'
try "Dailymotion"          '{"url":"https://www.dailymotion.com/video/x7tgad0","kind":"video","quality":"480"}'
echo; echo "== results"; cat results.txt
adb logcat -d -s python.stdout python.stderr | tail -n 200 > python-log.txt
adb logcat -d | grep -E "AndroidRuntime|FATAL" | tail -n 60
echo "$ST" | grep -q '"qjs":"ok"' && echo "$ST" | grep -q '"ffmpeg":"ffmpeg version' || { echo "::error::built-in helpers did not run"; exit 1; }
