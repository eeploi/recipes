# Contributing

Contributions are welcome, under the [MIT license](../LICENSE.md) like the rest of the repo. No CLA.

1. Open an issue first, and say what you want to change and why.
2. Then send a small pull request with that one change.

Before a pull request, run:

```bash
git ls-files '*.sh' | xargs -n1 bash -n
bin/check-layout.sh
bin/render.sh | shellcheck -e SC1091 -
bin/render.sh --no-first-boot | shellcheck -e SC1091,SC2034 -
bin/render.sh --checks | shellcheck -e SC1091 -
shellcheck bin/*.sh stack/fingerprint.sh
```

CI runs these and the repo's tests on every pull request; `.github/workflows/ci.yml` lists them.

Report a security problem as the [security policy](SECURITY.md) describes, never in an issue or a pull request.

Never put server names, IP addresses or secrets in an issue or a pull request. Use fictional ones, such as `shop.example` and the documentation IP ranges.
