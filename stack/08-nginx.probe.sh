#!/usr/bin/env bash
# Probe: nginx. The config nginx reads, after every include (nginx -T), cut to these directives:
# per server block its listens and server names and whether it refuses the TLS handshake, and a
# few http settings. Never a certificate, a key or any other directive. No nginx: no lines.
# README, Probes.
# Lines: server <n> file <path>, server <n> <directive> <arguments>, http <directive> <arguments>;
# n counts the server blocks in the order nginx -T prints them.
set -euo pipefail
# The settings whose values are safe to show.
safe=(listen server_name ssl_reject_handshake server_tokens fastcgi_buffer_size fastcgi_buffers
  real_ip_header set_real_ip_from)
[ "${1:-}" != --safe ] || { printf '%s\n' "${safe[@]}"; exit 0; }

command -v nginx > /dev/null || exit 0
# D-17: nginx -T reads the config on disk, not the running nginx.
config=$(nginx -T 2> /dev/null)
# nginx's own parsing, in short: words split by spaces, a quoted string is one word, # starts a
# comment only where a word starts, and ; { } end a directive. So a ; or a directive's name
# inside quotes or a comment is never taken for one. nginx -T prints each file on its own, an
# included one after the file that includes it, so each starts at the top: a server block at the
# top of a file is one that http or stream included, and a directive there is an http one. Limit:
# so is one from a file included inside a server block, such as a snippet.
# shellcheck disable=SC2016 # awk's $
awk -v server_dirs=' listen server_name ssl_reject_handshake ' \
  -v http_dirs=' server_tokens fastcgi_buffer_size fastcgi_buffers real_ip_header ' '
function word() { if (tok != "" || quoted) { args[n++] = tok }; tok = ""; quoted = 0 }
function directive(   i, s) {
  if (n == 0) return
  if (stack[depth] == "server" && id[depth]) {
    if (index(server_dirs, " " args[0] " ")) { s = "server " id[depth] " " args[0]; for (i = 1; i < n; i++) s = s " " args[i]; print s }
  } else if (depth == 0 || (depth == 1 && stack[1] == "http")) {
    if (index(http_dirs, " " args[0] " ")) { s = "http " args[0]; for (i = 1; i < n; i++) s = s " " args[i]; print s }
  }
  n = 0
}
function block_start() {
  depth++
  stack[depth] = n > 0 ? args[0] : ""
  id[depth] = 0
  if (stack[depth] == "server" && (depth == 1 || stack[depth - 1] == "http" || stack[depth - 1] == "stream")) {
    servers++; id[depth] = servers; print "server " servers " file " file
  }
  n = 0
}
function block_end() { n = 0; if (depth > 0) depth-- }
BEGIN { depth = 0; n = 0; tok = ""; quoted = 0; q = ""; file = "-" }
q == "" && /^# configuration file .*:$/ { file = substr($0, 22, length($0) - 22); depth = 0; n = 0; tok = ""; quoted = 0; next }
{
  line = $0 "\n"
  len = length(line)
  for (i = 1; i <= len; i++) {
    c = substr(line, i, 1)
    if (q != "") {
      if (c == "\\") { tok = tok substr(line, i + 1, 1); i++ }
      else if (c == q) { q = "" }
      else tok = tok c
      continue
    }
    if (tok == "" && !quoted && c == "#") break
    if (tok == "" && !quoted && (c == "\"" || c == "\047")) { q = c; quoted = 1; continue }
    if (c == " " || c == "\t" || c == "\r" || c == "\n") { word(); continue }
    if (c == ";") { word(); directive(); continue }
    if (c == "{") { word(); block_start(); continue }
    if (c == "}") { word(); n = 0; block_end(); continue }
    if (c == "\\") { tok = tok c substr(line, i + 1, 1); i++; continue }
    tok = tok c
  }
}' <<< "$config"
