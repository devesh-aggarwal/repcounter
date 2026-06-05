# App Store Submission Pack — GymTrack

Drop-in metadata for App Store Connect. Limits noted next to each field.

---

## App Name (30 chars max)

```
GymTrack: Lifts & Progress
```

> Search the App Store for "GymTrack" before locking this in — if there's a
> close-name collision, swap to one of: "GymTrack Lift Log", "LiftTrack",
> "Plate Progress".

## Subtitle (30 chars max)

```
Log every lift. See progress.
```

## Promotional Text (170 chars — editable post-launch)

```
Track every set with a single slider. PR detection, plate calculator, rest timer, and progression charts — all on-device, no account, no ads.
```

## Description (4000 chars max)

```
GymTrack is the fastest way to log a workout on iPhone.

One slider per exercise. Move it, and your set is saved. Plate calculator does the math. Rest timer ticks in the background. Personal records light up the moment you hit them. Everything stays on your phone — no account, no sync, no ads, no tracking.

WHY GYMTRACK

• ONE-TAP LOGGING. The slider is the log. No "add set" screen, no "save" button, no friction. You can finish a session without ever leaving the Today tab.

• REAL PR DETECTION. Hit a new best and the card celebrates. No guessing whether you actually progressed.

• PLATE CALCULATOR. Tell it the target weight; it tells you the plates per side. Works for lbs and kg bars.

• REST TIMER WITH NOTIFICATIONS. Start a timer per exercise. Lock your phone — you'll get a notification when it's time to lift again.

• PROGRESSION CHARTS. See every exercise over time, on a clean dark chart anchored at zero so growth actually reads.

• WEEKLY SCHEDULE. Tell the app which workout belongs to which day of the week. Open the app on Monday, see Monday's lift, no scrolling.

• PUSH / PULL / LEGS BUILT IN. Categorize exercises by split day. The app remembers which is which.

• CSV EXPORT. Pull your full history out as a CSV any time. Your data, your call.

DESIGNED FOR HONEST PROGRESS

GymTrack was built around one idea: the easier it is to log a set, the more sets you log, and the more honest your progress data becomes. Everything else — the charts, the records, the insights — is downstream of one well-designed slider.

PRIVACY YOU CAN VERIFY

GymTrack has no accounts, no servers, no analytics SDKs, and no third-party tracking. Your data is stored on your device using Apple's standard SwiftData framework. We don't see it. Apple doesn't see it. Nobody does. Deleting the app deletes the data.

PERFECT FOR

• Strength training (3- or 4-day push/pull/legs splits)
• Bodybuilding programs that revolve around progressive overload
• Anyone tired of fitness apps that demand a subscription, a sign-up, or both

NO SUBSCRIPTION, NO ACCOUNT, NO TRACKING. JUST LIFT.
```

## Keywords (100 chars total, comma-separated, no spaces after commas)

```
gym,workout,lift,strength,tracker,log,pr,plate,calculator,rest,timer,progress,split,push,pull,legs
```

## Primary Category

```
Health & Fitness
```

## Secondary Category

```
Productivity
```

## Age Rating

`4+` (no restricted content)

---

## Support URL (required)

You need a public page. Cheapest path: a one-page GitHub Pages site at
`https://<your-username>.github.io/gymtrack-support/` with a contact email and
a sentence saying "Email me at … and I'll respond within X business days."

## Marketing URL (optional, recommended)

Same site, or omit.

## Privacy Policy URL (required)

You need a public privacy policy page. Suggested text (copy to a `.md` file
and publish on GitHub Pages):

```
PRIVACY POLICY — GymTrack

Last updated: 2026-05-28

GymTrack does not collect, transmit, store on remote servers, or share any
personal data. All workout history, exercise definitions, and preferences are
stored only on your device using Apple's SwiftData framework. The app makes no
network requests and contains no third-party analytics, advertising, or
tracking SDKs.

The only system permission the app requests is notifications, which are used
exclusively to alert you when your rest timer completes. No notification
content is transmitted off-device.

If you uninstall GymTrack, all stored data is removed by iOS. If you would
like to back up your data, use the "Export CSV" feature inside the app's
Settings screen.

Contact: <your-email>
```

---

## Privacy Nutrition Label (App Privacy → Data Types)

Select **"Data Not Collected"** for every category. That's the entire form.
This is the truthful answer and the easiest review path.

App Tracking Transparency: **Not used** (you don't track users across apps).

---

## Screenshots Required

You **must** provide screenshots at these sizes for iPhone-only submission:

| Display Size | Device                                  | Required? |
|--------------|-----------------------------------------|-----------|
| 6.9" / 6.7"  | iPhone 17 Pro Max / 16 Pro Max          | Required  |
| 6.1"         | iPhone 17 / 16                          | Required  |

5–8 screenshots per size. Suggested shot list (in this order):

1. **Today tab** — slider mid-drag, clear weight number.
2. **Day selector** — segmented Push/Pull/Legs/Misc visible.
3. **Plate calculator sheet** — shows the per-side breakdown.
4. **Stats summary** — workouts this week + week streak + total gained.
5. **Progression chart** — Smith Machine Press All-time.
6. **Settings** — weekly schedule editor.
7. **Rest timer bar** — overlay showing live countdown.

Generate using simulator (`Cmd+S` saves a PNG to Desktop). Sizes auto-export
at the required resolution.

---

## Build / Submission Prerequisites

Before Archive → Distribute, verify:

- [ ] Apple Developer Program enrolled ($99/yr)
- [ ] Bundle identifier set to a unique reverse-DNS string in
      `GymTrack.xcodeproj > Signing & Capabilities`
- [ ] Development Team selected (**this is what's blocking your current build**)
- [ ] Version: `1.0.0`, Build: `1`
- [ ] Marketing icon (already present at 1024×1024)
- [ ] Push Notifications capability NOT added (we use local
      `UNTimeIntervalNotificationTrigger`, which does not need the cap)
- [ ] `Info.plist` includes a usage string for `NSUserNotificationsUsageDescription`
      if one isn't already inferred. The system handles the rest timer prompt
      via `requestAuthorization` at runtime.
- [ ] Test on a real device once before submitting — simulators don't surface
      every signing issue.
- [ ] First-launch test: install fresh, confirm the seeded starter exercises
      appear but no history is present (i.e. the chart shows an empty state).

---

## App Review Notes (text to paste in App Store Connect)

```
GymTrack is a fully offline workout tracker. No account is required and no
data leaves the device. The app uses local notifications for an in-app rest
timer; users are prompted on first use.

To exercise the core flow:
1. Open the app — the "Today" tab opens to a starter workout for today's
   weekday (Monday → Push by default).
2. Drag any slider to change a weight; release. The value commits after a
   30-second grace window to forgive accidental edits.
3. Switch tabs to "Summary" to see the chart and stats.
4. Tap the gear icon for Settings, including unit (lbs/kg), weekly schedule,
   CSV export, and erase-all-data.

No demo account needed.
```

---

## Likely-Rejection Mitigations

These are the issues App Review most commonly flags for fitness trackers.
Each is already addressed:

| Common rejection                                      | Status                |
|-------------------------------------------------------|-----------------------|
| 2.1 — Hard-coded imperial units                       | ✅ lbs/kg toggle in Settings + per-exercise override |
| 2.1 — Fake seed data shown in screenshots             | ✅ Seeded exercises have no logged history          |
| 4.2 — Minimum functionality ("just a glorified note") | ✅ PR detection, plate calc, rest timer, charts, CSV export differentiate it |
| 5.1.1 — Vague privacy policy                          | ✅ Privacy policy template above is specific and verifiable |
| 5.1.1 — Excess data collection                        | ✅ Zero data collection                              |
| Missing notifications usage string                    | Verify in `Info.plist` — Xcode often adds it automatically |
| Accessibility                                         | ✅ VoiceOver labels on slider/buttons; segmented controls and Form rows are native-accessible |

Estimated odds of first-submission approval with this pack and a clean
build: **90–95%**. Most apps that get rejected on first submission fall to
one of the issues above; this submission addresses each.
