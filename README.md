# Running Commu check-in

A small web app for a running community. Runners sign in on their own phone, tap the checkpoint's NFC tag to log a lap, and follow the event leaderboard and a live map with everyone's avatar.

- **Check in:** tap the phone on the checkpoint's NFC tag (Chrome on Android), or press Check in. GPS is saved with each lap when the runner allows it.
- **Leaderboard:** runners (and groups, if you use them) ranked by km for the current event.
- **Map:** street map with checkpoints and each runner's photo where they last checked in.
- **Runner:** your profile and photo, all runners, optional groups, and event setup for organisers.

It is a static site (plain HTML and JS, no build step) hosted on GitHub Pages, with Supabase for logins and shared data.

## Set up

1. **Supabase project.** Create a free project at supabase.com. Open **SQL Editor**, paste all of `supabase/schema.sql`, and press **Run**.
2. **Keys.** In Supabase, open **Project Settings > API** and copy the **Project URL** and the **anon public** key into `config.js`.
3. **Login redirect.** In Supabase, open **Authentication > URL Configuration** and set **Site URL** to the GitHub Pages address, for example `https://<user>.github.io/running-commu/`.
4. **GitHub Pages.** In the repo, open **Settings > Pages**, choose **Deploy from a branch**, branch `main`, folder `/ (root)`.
5. **First sign-up is the organiser.** Open the site, create your account, and join. You can then add checkpoints and the event in the Runner tab under Event setup. To make someone else an organiser, run in the SQL Editor:
   `insert into admins (user_id) select id from auth.users where email = 'their@email.com';`

Optional: to let runners sign up without confirming their email, turn off **Authentication > Providers > Email > Confirm email**.

## NFC tags

Any NTAG213/215/216 sticker works. Stick one at each checkpoint, then in Event setup press **Scan tag** next to the checkpoint and hold the phone to it. Web NFC needs Chrome on Android and HTTPS (GitHub Pages is HTTPS). iPhones can't read NFC from a web page, so they use the Check in button.

## Files

- `index.html`: the whole app
- `config.js`: your Supabase URL and anon key
- `supabase/schema.sql`: tables, access rules, and live updates
- `vendor/`: Leaflet 1.9.4 (map) and supabase-js 2.100.0, kept in the repo so the site has no runtime CDN dependency

Map tiles © OpenStreetMap contributors © CARTO.
