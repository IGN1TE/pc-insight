# PC Insight progress

- [x] Guided GPU core trial: baseline, reviewed +15 MHz step, retests and result (user confirmed).
- [x] GPU cancellation restores original clocks (user confirmed).
- [x] GPU Keep, close/reopen, restore original clocks (user confirmed).
- [x] GPU 5/10-minute endurance observation, Stop and persistence (user confirmed).
- [x] CPU inventory and page layout (user confirmed on 0.27.1).
- [x] CPU three-run baseline: 3/3 matching runs, 1.2% spread (user confirmed).
- [x] CPU cancellation and saved-baseline retention (user confirmed).
- [x] Documented interface for bounded Intel package power limits (Intel SDM + PawnIO module).
- [x] CPU package power implementation and automated failure/recovery checks (0.28.0).
- [ ] Windows CPU detection, apply, readback and restoration acceptance.
- [ ] CPU multiplier and voltage controls: supported interface and validation still required.
- [ ] Clearer results dashboard.
- [ ] Automated Windows release checks.
- [ ] Installer/layout polish.

The CPU power preview is limited to decreasing PL1/PL2 on the initial i7-13700K / CPUID B7 target. It does not add multiplier overclocking or voltage control. Do not mark physical validation or CPU stability complete from mocked tests.
