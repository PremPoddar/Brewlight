# Privacy

Brewlight collects nothing about you and has no analytics of its own.

It makes these network requests:

- **formulae.brew.sh** — package metadata (only when Homebrew's local cache is missing) and
  public install statistics. Can be turned off in Settings → Privacy.
- **Package homepages and GitHub avatars** — to fetch icons. Can be turned off in
  Settings → Privacy.
- **GitHub** — the Homebrew installer package, if you choose to install Homebrew from the app.

Your tags, notes, favourites and history stay on your Mac in
`~/Library/Application Support/Brewlight`. Administrator passwords are passed straight to
`sudo` by the system prompt and are never stored.
