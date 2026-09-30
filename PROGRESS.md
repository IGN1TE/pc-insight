# PC Insight progress

- [x] Guided core trial: baseline, reviewed +15 MHz step, retests and result (user confirmed).
- [x] Cancellation restores original clocks (user confirmed).
- [x] Keep, close/reopen, restore original clocks (user confirmed).
- [x] Implement 5/10-minute GPU endurance observation with mocked automated checks.
- [x] Validate endurance completion, Stop, restart and 10-minute run on the user's Windows GPU (user confirmed).
- [x] CPU tuning readiness: inventory, explicit availability, baseline launch and report export (implemented; Windows UI acceptance pending).
- [ ] Direct CPU tuning: validated vendor adapter, controls, readback and restoration.
- [ ] Clearer results dashboard.
- [ ] Automated Windows release checks.
- [ ] Installer/layout polish.

Endurance acceptance: run 5 minutes at original settings, confirm saved elapsed time and temperature; start another run and Stop, confirm a partial stopped result; reopen and check the saved result. Run 10 minutes only after the 5-minute and Stop checks pass. Record any graphics artifacts, errors, driver reset or crash separately. Do not treat completion as proven stability.
