# VisitedStates v1.1.2 Release Notes

## Release Date: May 16, 2025

## What's New

### New Badge: Road Trippin'
- Added a new special achievement badge called "Road Trippin'"
- Awarded for visiting 5 unique states within a 7-day span
- Features a purple/violet background with a car icon
- Perfect for tracking those epic road trip achievements!

## Improvements

### Bug Fixes
- Fixed visual issue where background colors with opacity appeared differently in map areas versus edges
- Fixed App Store rejection issues with permission request flow:
  - Changed permission button text from "Request Access" to "Continue"
  - Removed back button from permission screens to comply with Apple guidelines
- Fixed notification cooldown logic that incorrectly prevented notifications after 30 seconds

### Internal Updates
- Updated app version to 1.1.2
- Updated documentation to include the new Road Trippin' badge
- Code cleanup and optimization

## Technical Details

### Badge System Enhancement
- Added new special condition type: `uniqueStatesInDays(count: Int, days: Int)`
- Implemented rolling window detection for multi-day badge requirements
- Badge is awarded immediately upon visiting the 5th unique state within any 7-day period

### Map Rendering Fix
- Removed layered background modifiers that caused opacity issues
- Ensured consistent background color rendering across all map views

## Known Issues
- None at this time

## Coming Soon
- Additional badge types and achievements
- Enhanced badge tracking features

---

VisitedStates v1.1.2 - Track your US state visits automatically!