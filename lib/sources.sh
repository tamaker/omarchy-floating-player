#!/bin/bash
# shellcheck disable=SC2034 # every variable here is read by name via fp_source
# Source table for the floating player. Sourced by bin/floating-player and the
# sign-in / scan helpers. One browser profile per source so sign-in state and
# user agents never leak between sources. Findings behind these values:
# docs/signin.md.
#
#   FP_SOURCES                    list of source names
#   fp_source <name> <field>      prints a field ("" if unset); fields:
#     title         display name ("YouTube", "YouTube TV")
#     url           start page
#     profile       profile dir name under $FP_DATA/profiles/
#     ua            user agent ("" = browser default)
#     signin_url    page that starts sign-in
#     signin_hint   one-line instructions for the sign-in screen
#     signin_keys   keys (xkb names) sent to the player window once the sign-in
#                   page has loaded, to get from the welcome screen to the QR
#                   code ("" = none)
#     auth          how `floating-player-signin --check` detects a session:
#                     tvapp:<prefix>  TV-app identity in the profile's
#                                     localStorage ("<prefix>::available-identities")
#                     cookies         Google session cookies (SAPISID, …)
#
# Environment:
#   FP_YOUTUBETV_MODE=tv   (default) YouTube TV's living-room app at
#                          www.youtube.com/tv/upg, phone-QR sign-in
#   FP_YOUTUBETV_MODE=web  the desktop site tv.youtube.com with the browser's own
#                          UA and a normal Google sign-in (fallback in case the
#                          TV app refuses to play here; see docs/signin.md)
#   FP_TV_UA=…             override the TV user agent

FP_SOURCES=(youtube youtubetv)

# YouTube's living-room apps (leanback /tv and YouTube TV's /tv/upg) want a TV
# user agent (a desktop UA on /tv is redirected to youtube.com). Tested 2026-10:
# this Samsung Tizen UA gets the TV app, its phone-QR sign-in and MSE playback in
# Chromium 152. Cobalt and webOS UAs work too; a Chromecast (CrKey) UA only gets
# an idle "Ready to cast" receiver screen.
: "${FP_TV_UA:=Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36}"

# --- YouTube: the leanback TV app ------------------------------------------
# No URL opens the sign-in screen directly (every hash route is rewritten to
# "#/"). Signed out, /tv starts on "Get started" (first run) or the account
# picker ("Add account"), both focused by default; Enter there shows the QR code.
fp_source_youtube_title='YouTube'
fp_source_youtube_url='https://www.youtube.com/tv'
fp_source_youtube_profile='youtube'
fp_source_youtube_ua="$FP_TV_UA"
fp_source_youtube_signin_url='https://www.youtube.com/tv'
fp_source_youtube_signin_hint='Scan the QR code in the player with your phone camera, or open yt.be/activate on your phone and type the code shown. No QR code? Press Enter in the player (or click "Get started" / "Add account").'
fp_source_youtube_signin_keys='Return'
fp_source_youtube_auth='tvapp:yt.leanback.default'

# --- YouTube TV --------------------------------------------------------------
fp_source_youtubetv_title='YouTube TV'
fp_source_youtubetv_profile='youtubetv'
if [[ ${FP_YOUTUBETV_MODE:-tv} == web ]]; then
  fp_source_youtubetv_url='https://tv.youtube.com/'
  fp_source_youtubetv_ua=''
  fp_source_youtubetv_signin_url='https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Ftv.youtube.com%2F'
  fp_source_youtubetv_signin_hint='Sign in with your Google account in the player. Google may offer "Tap Yes on your phone"; a passkey QR ("Use a phone or tablet") also needs working Bluetooth on this computer.'
  fp_source_youtubetv_signin_keys=''
  fp_source_youtubetv_auth='cookies'
else
  # YouTube TV's own living-room app (what smart TVs run). Its welcome page has
  # "Member sign-in" (Up from the default focus), which shows a QR code for
  # tv.youtube.com/start. Signed in, it plays live TV here (Widevine L3).
  fp_source_youtubetv_url='https://www.youtube.com/tv/upg'
  fp_source_youtubetv_ua="$FP_TV_UA"
  fp_source_youtubetv_signin_url='https://www.youtube.com/tv/upg'
  fp_source_youtubetv_signin_hint='Scan the QR code in the player with your phone camera, or go to tv.youtube.com/start and enter the code shown. No QR code? Click "Member sign-in" in the player.'
  fp_source_youtubetv_signin_keys='Up Return'
  fp_source_youtubetv_auth='tvapp:yt.tv.upg'
fi

# fp_source <name> <field>  -> prints the value
fp_source() {
  local var="fp_source_${1}_${2}"
  printf '%s' "${!var-}"
}
