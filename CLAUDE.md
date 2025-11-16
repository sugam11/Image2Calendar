# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Image2Calendar is an iOS SwiftUI application that uses OCR (Optical Character Recognition) to extract calendar events from images and add them to the user's iOS Calendar. The app scans images of calendars (like screenshots or photos of weekly schedules) and automatically detects event titles, times, and days.

## Building and Running

This is an Xcode project for iOS. To build and run:

- Open `Image2Calendar.xcodeproj` in Xcode
- Select a simulator or connected device
- Use Cmd+R to build and run, or Cmd+B to build only
- The app requires iOS 16+ (iOS 17+ for full calendar access features)

## Architecture

### Core Data Flow

1. **Image Selection** → User selects an image via PhotoPicker
2. **OCR Processing** → Vision framework extracts text with bounding boxes
3. **Event Parsing** → EventParser analyzes text positions to determine day columns and extract event details
4. **Calendar Integration** → Events are added to the iOS Calendar via EventKit

### Key Components

**OCRViewModel** (Image2Calendar/ViewModels/OCRViewModel.swift:16)
- Main view model coordinating the entire OCR-to-calendar flow
- Uses Vision framework's `VNRecognizeTextRequest` for text recognition
- Delegates parsing to EventParser
- Handles calendar access and event creation via EventKit
- All operations are `@MainActor` for thread safety

**EventParser** (Image2Calendar/ViewModels/EventParser.swift:27)
- Spatial parsing algorithm that analyzes text bounding boxes
- Handles titles and times on **separate text observations** (common in OCR output)
- `detectDayHeaders()` identifies day column positions (Mon, Tue, Wed, etc.) based on exact text matching
- `extractTimeRange()` extracts time ranges using regex pattern `(\d{1,2}:\d{2})\s*(am|pm)?\s*[-–]\s*(\d{1,2}:\d{2})\s*(am|pm)?` (supports both 12-hour and 24-hour formats)
- `findNearbyTitle()` searches for text above time observations using spatial proximity (EventParser.swift:89)
- `dayForPosition()` maps events to days by comparing X-positions to detected column positions
- `nextDate()` calculates the next occurrence of each weekday from today
- Events are automatically sorted by date/time after parsing (OCRViewModel.swift:70)

**PhotoPicker** (Image2Calendar/Views/PhotoPicker.swift:12)
- UIKit wrapper using `PHPickerViewController` for image selection
- Implements `UIViewControllerRepresentable` to bridge UIKit into SwiftUI
- Returns UIImage via binding and completion handler

### Data Models

**ScannedEvent** (Image2Calendar/Models/ScannedEvent.swift:11)
- Core event model with title, startDate, optional endDate, and optional location
- `Identifiable` for SwiftUI List iteration
- Location field stored in event description for calendar integration

**ParsedEventLine** (Image2Calendar/ViewModels/EventParser.swift:13)
- Internal parsing model that includes X-position for spatial column detection
- Used temporarily during parsing before creating ScannedEvent

### Important Implementation Details

**Spatial Parsing Strategy**
The parser handles OCR output where titles and times are separate observations:
1. **Day Column Detection** - Exact matches only for day names to avoid false positives like "Sun" in "Sunrise" (EventParser.swift:125)
2. **Time Detection** - Finds all observations containing time ranges (EventParser.swift:49)
3. **Title Association** - For each time observation, searches for nearby text above it within 10% vertical distance and 5% horizontal alignment (EventParser.swift:89)
4. **Day Assignment** - Maps events to days by comparing X-positions to detected column positions (EventParser.swift:145)

**Time Parsing**
- Supports both 12-hour format with am/pm (e.g., "7:30 am - 9:30 am") and 24-hour format (e.g., "13:00-14:00")
- Regex pattern: `(\d{1,2}:\d{2})\s*(am|pm)?\s*[-–]\s*(\d{1,2}:\d{2})\s*(am|pm)?` (EventParser.swift:154)
- DateFormatter handles both "h:mm a" and "H:mm" formats (EventParser.swift:130)
- Defaults to 1-hour duration if end time is missing

**Event Sorting and Batch Operations**
- Events automatically sorted by startDate after parsing (OCRViewModel.swift:70)
- "Add All to Calendar" batch operation available (OCRViewModel.swift:115)
- Individual events can be added one at a time

**Calendar Permissions**
- iOS 17+ uses `requestFullAccessToEvents` (OCRViewModel.swift:93)
- Earlier versions use deprecated `requestAccess(to: .event)` (CalendarManager.swift:17)
- Permission requests happen inline when user taps "Add to Calendar" or "Add All to Calendar"
- Location field is saved to iOS Calendar events when available (OCRViewModel.swift:99)

## Concurrency Notes

- OCRViewModel is marked `@MainActor` to ensure UI updates happen on main thread
- Vision API calls run on `DispatchQueue.global(qos: .userInitiated)` (OCRViewModel.swift:57)
- Results are dispatched back to main thread via `DispatchQueue.main.async` (OCRViewModel.swift:46)
- Vision and EventKit imports use `@preconcurrency` to suppress Swift 6 warnings (OCRViewModel.swift:10,13)

## Current Limitations

- Only parses events with explicit time ranges (requires "H:MM - H:MM" format with am/pm or 24-hour)
- Assumes all events are in the upcoming week (uses `nextDate()` calculation from today)
- Day detection relies on spatial X-position proximity, which may fail with unusual layouts
- Title detection uses vertical proximity (within 10%) which may miss titles that are far from time
- Location detection not yet implemented (placeholder exists at EventParser.swift:118)
- No support for all-day events or multi-day events
- Calendar access is requested per-operation (not upfront)
