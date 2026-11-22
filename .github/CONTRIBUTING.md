# Contributing

Contributions are welcome. They are licensed under the [MIT license](../LICENSE.md), as the rest of the repo; there is no CLA to sign.

1. Open an issue first, and say what you want to change and why.
2. Then send a small pull request for it, one change at a time.

Before a pull request, run:

```bash
git ls-files '*.sh' | xargs -n1 bash -n
bin/check-layout.sh
bin/render.sh | shellcheck -e SC1091 -
bin/render.sh --checks | shellcheck -e SC1091 -
shellcheck bin/*.sh stack/fingerprint.sh
```

CI runs these and the repo's tests on every pull request; `.github/workflows/ci.yml` lists them.

A security problem never goes in an issue or a pull request: report it as [SECURITY.md](SECURITY.md) describes.

Never put server names, IP addresses or secrets in an issue or a pull request. Use fictional ones, such as `shop.example` and the documentation IP ranges.
