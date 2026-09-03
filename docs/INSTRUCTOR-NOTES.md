# Instructor notes

## Why this shape

Students who deploy a portfolio page to IIS learn IIS and nothing else. The page is inert — if it renders, they are done, and nothing forces them to understand the platform under it.

Here the page cannot render correctly unless three separate layers are right: IIS installed, a site bound, and the collector running. Each failure has a distinct signature on screen, so a stuck student can usually tell you *which* layer is broken before you look.

The scripts touch no cloud API, which is what makes this portable. The cloud content comes from three places instead:

- **Two firewalls.** Nearly every student who cannot reach the page from their laptop has one right and the other wrong.
- **The public IP the machine cannot see.** `ipconfig` shows a private address. The card shows a public one. The gap between those is the clearest demonstration of cloud NAT you can get in one screen.
- **Outbound is free, inbound is not.** The collector's call to `api.ipify.org` needs no configuration. The laptop's inbound request needs two rules. Students rarely notice this asymmetry until you point at it.

Zero web development is required. If a student starts editing `index.html`, they have misread the assignment.

---

## Before the session

- [ ] Fork or upload the repo, then **update the ZIP URL** in README Step 1 to your actual repo.
- [ ] Decide which cloud (or let students choose — the package is the same either way).
- [ ] Run it yourself on a fresh VM the day before. Windows image patch levels shift.
- [ ] Confirm `api.ipify.org` is reachable from your training network and from the VMs. If outbound HTTPS is filtered, the public-IP lesson is the one thing that breaks — have `checkip.amazonaws.com` and `ifconfig.me` as fallbacks (the script already tries all three).
- [ ] Decide whether students create their own VMs or you pre-create them. Pre-creating costs you Step 0 but saves 20 minutes and most of the support load.
- [ ] Keep one finished VM of your own, so a stuck student can still see the working state.

---

## Timing (75 min)

| Min | Segment |
|---|---|
| 0–8 | Framing. Show your finished card. Ask: where did this data come from, and how did it get into the browser? Let them guess wrong. |
| 8–28 | Step 0 — create the VM, get the password, RDP in. The slowest and most support-heavy part. |
| 28–42 | Step 1 — edit `deployment.json`, run setup. Use the install wait to draw the two-firewall model on the board. |
| 42–55 | Step 2 — **the core of the session.** Do the `ipconfig` vs the card comparison together, on screen. |
| 55–65 | Step 3 — scheduled task. Have everyone disable it at the same moment and watch the room's dashboards go amber, then red. |
| 65–75 | Steps 4–5, cleanup, debrief. **Do not let anyone leave without deleting their VM.** Verify on screen. |

For 60 minutes: pre-create the VMs.
For 120 minutes: add challenges 2 and 5, and the reboot/stop-start experiments as a live demo.

---

## Moments worth pausing on

**`ipconfig` vs the card.** Put them side by side on the projector. Ask where the public address is stored if not on the machine. This is the single highest-value minute in the lab.

**The disabled task.** The page keeps serving fine and simply reports being stale. Ask: *if this were a real monitoring page, what would have gone wrong that nobody noticed?*

**Why SYSTEM.** Ask why not Administrator. Answers: no stored password to rotate or leak, survives logoff, conventional for machine-scoped background work. Then ask what production would actually use — a dedicated least-privilege account, or not writing into the web root at all.

**GCP's default-allow-rdp.** If anyone is on GCP, this is a gift: the default VPC ships with RDP open to the world. Have them find it, explain why Google ships it, and replace it with a tagged rule. Cross-cloud, ask the AWS and Azure students what their equivalent default was.

---

## Grading (100 points)

| # | Criterion | Pts |
|---|---|---|
| 1 | VM created; firewall scoped to their own IP, not `0.0.0.0/0` | 15 |
| 2 | IIS installed; site published as a named site with its own app pool and correct binding | 20 |
| 3 | `deployment.json` filled in accurately for their actual VM | 10 |
| 4 | Card renders live data for **their** machine | 15 |
| 5 | Scheduled task registered and demonstrably keeping the page fresh | 15 |
| 6 | Page reachable from the student's own laptop | 10 |
| 7 | Written answers — accuracy and reasoning | 10 |
| 8 | VM and disk deleted after the session | 5 |

Mark the submission zero if a screenshot shows 3389 open to `0.0.0.0/0`. That is the habit most worth breaking early — and on GCP it takes deliberate action to avoid, which is exactly the point.

Bonus: up to 10 points for any optional challenge. Challenge 6 (deploy on a second cloud) is the strongest, and pairs well with a short written comparison.

---

## Failures you will see, in order of frequency

1. **Not elevated.** Every script checks and says so, but students still miss it.
2. **Wrong directory.** They extracted to Downloads and are `cd`'d elsewhere. `Get-Location` first.
3. **`deployment.json` left with the placeholder name.** Script 1 warns; script 4 fails the check.
4. **Nested folder after Expand-Archive.** GitHub's ZIP adds a `-main` suffix folder; students `cd` one level short.
5. **Cloud firewall scoped to their morning IP.** Their address changed when they switched networks.
6. **Typing `https://`.** Browsers increasingly force it. Warn them up front.
7. **Editing the HTML** because "the page says there's an error". Redirect them — the error is accurate and the fix is upstream.

---

## Where to go next

This lab deliberately leaves the cloud-specific metadata services alone, which keeps it portable. If you want a follow-up session that goes deeper on one cloud, the natural next step is the instance metadata service — `169.254.169.254` on all three, with a different auth model on each. It answers "what does the machine know about itself that we had to type into `deployment.json` by hand?", which is a satisfying callback, and on AWS it opens directly onto IMDSv2 and the SSRF story behind it.
