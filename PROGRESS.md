# PC Insight progress

- [x] Guided core trial: baseline, reviewed +15 MHz step, retests and result (user confirmed).
- [x] Cancellation restores original clocks (user confirmed).
- [x] Keep, close/reopen, restore original clocks (user confirmed).
- [x] Implement 5/10-minute GPU endurance observation with mocked automated checks.
- [ ] Validate endurance completion, Stop and restart on the user's Windows GPU.
- [ ] CPU tuning support.
- [ ] Clearer results dashboard.
- [ ] Automated Windows release checks.
- [ ] Installer/layout polish.

Endurance acceptance: run 5 minutes at original settings, confirm saved elapsed time and temperature; start another run and Stop, confirm a partial stopped result; reopen and check the saved result. Run 10 minutes only after the 5-minute and Stop checks pass. Record any graphics artifacts, errors, driver reset or crash separately. Do not treat completion as proven stability.
