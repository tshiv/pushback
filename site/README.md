# pushback site

The landing page for [pushback](https://github.com/tshiv/pushback). One self-contained
`index.html` (no build step, no framework). Deploy it anywhere that serves static files.

## Files

- `index.html` — the whole page (CSS + JS inline)
- `og.svg` — social share card referenced by the OG meta tags
- `README.md` — this file

## Preview locally

```bash
cd site
python3 -m http.server 8080
# open http://localhost:8080
```

## Deploy

**Vercel** (what taylorshivers.com already uses)
- New Project → import `tshiv/pushback` → set the **Root Directory** to `site` → deploy.
- Framework preset: "Other". No build command. Output is the folder itself.

**GitHub Pages**
- Either move these files to a top-level `/docs` folder and set Pages → Source → `main` / `/docs`,
  or add a Pages action. Pages can't serve an arbitrary `/site` folder without an action.

## Custom subdomain (free, no new domain)

To mirror the `mojito.wells.ee` setup with `pushback.taylorshivers.com`:

1. In Vercel (or your host), add the domain `pushback.taylorshivers.com` to this project.
2. At your DNS provider, add a `CNAME` record: `pushback` → `cname.vercel-dns.com`
   (Vercel shows the exact target). On GitHub Pages, CNAME to `tshiv.github.io`.
3. Update the `og:url` / `canonical` in `index.html` to the final URL, and (optional) swap
   `og.svg` for a 1200×630 PNG so iMessage and Twitter always render the preview.
