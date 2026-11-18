# NaturalSearch

NaturalSearch is a macOS app for finding files with natural language. You type a request such as
*"PDFs about invoices from last month"*. Apple Intelligence's on-device language model turns it into a
structured Spotlight query. The query appears as editable filter rows, and the results update live,
much like the search window in the Finder.

The user interface is in German.

## Features

### Natural-language search
- The search field has three modes: **natural language (Apple Intelligence)**, **any text**, and **file name**.
- In natural-language mode, the on-device model (`FoundationModels`) extracts:
  - content keywords, each with up to three synonyms or translations (German ↔ English),
    e.g. *Rechnung → Beleg, Invoice*
  - terms that must appear in the file name
  - file extensions (`pdf`, `docx`, `key`, …) or a general content kind (image, movie, presentation, …)
  - a time range (today, last week, last month, …) and which date it refers to (modified, created, opened)
  - a location ("in the Downloads folder", "on the Desktop")
  - Finder color tags
- The app checks the model's output against the original request. It drops anything the request doesn't mention,
  such as made-up keywords, extensions, tags, time ranges, or locations.
- Without Apple Intelligence, the app falls back to a plain text search.

### Refine: Finder-style filter rows
- The interpreted request becomes rows of the form *attribute · operator · value*. You can edit them
  or build them by hand.
- Attributes: any text, name, text content, file extension, content kind, modified/created/last-opened date,
  size, author, and comment.
- Operators include *contains*, *does not contain*, *begins with*, *ends with*, *is*, *is not*,
  *contains prefixes/words*, *within the last N days*, *older than N days*, *is today*, and *greater/less than*.
- Boolean logic: rows are joined with **and** / **or**. *And* binds tighter than *or*. Rows can be put into
  **nested groups** (parentheses), and each row or group can be negated (**not**).
- Per row, you can choose case-sensitive and diacritic-sensitive matching.
- You can filter by Finder color tags, set a result limit (100 to 100,000), and choose the sort date and direction.
- You can copy the generated Spotlight query (MDQuery syntax, as used by `mdfind`) to the clipboard.

### Results
- The app runs a live Spotlight search (`NSMetadataQuery`), so results update when files change.
- You can show results as a sortable table or as an icon grid.
- **Relevance ranking**: matches in the file name come first, and recently used files get a bonus.
- You can open a file, show it in the Finder, or copy its path, for one file or many.

### Info pane
- **Info**: file metadata (kind, dates, size, tags, comment, path).
- **Preview**: Quick Look preview of the selected file.
- **Summary (Apple Intelligence)**:
  - summarizes the whole result list (topics, folders, time ranges, file types)
  - summarizes the content of a selected document (PDF, plain text, RTF/Office)
  - answers questions about your files. The model searches the Spotlight index with
    `SpotlightSearchTool` and lists the files it used. You can click a file to open it.

### Saved and recent requests
- The app remembers your last ten requests, and you can save any request permanently.
- A separate window lists your saved requests. Double-click a request to run it again.

### Menu bar extra
- A compact search panel in the menu bar, with a search field, the top results, a folder picker,
  and your saved and recent requests.
- It shares its search state with the main window, so it keeps searching while the window is closed.

### Shortcuts
- The App Intent **"Dateien suchen"** (Search Files) passes a request to NaturalSearch and runs it. The request
  is interpreted exactly as if you had typed it in the search field.

## Locations and privacy

NaturalSearch runs in the App Sandbox. It only searches folders that you explicitly grant access to under
**Orte** (Locations), such as your home folder, Documents, Downloads, Desktop, or any other folder. The app
stores this access as security-scoped bookmarks. You can exclude specific folders from the search.

All language processing runs **on device** with Apple Intelligence, and no file content leaves your Mac.

## How it works

```
Search field → QueryParser (Foundation Model) → FileSearchQuery → Refine rows
             → PredicateBuilder → NSPredicate → SpotlightSearch (NSMetadataQuery) → Results
```

| Folder | Contents |
| --- | --- |
| `NaturalSearch/AI` | `QueryParser`, the `@Generable` `FileSearchQuery` and its normalization, `ResultSummarizer` |
| `NaturalSearch/App` | App entry point, `SearchModel` (central observable state) |
| `NaturalSearch/Intents` | `SearchFilesIntent` for Shortcuts |
| `NaturalSearch/Models` | Filter criteria, groups, options, results, tags, content kinds |
| `NaturalSearch/Search` | Predicate building, Spotlight wrapper, relevance ranking, locations, saved queries |
| `NaturalSearch/Views` | SwiftUI views: main window, refine/results/info panes, menu bar panel |
| `NaturalSearchTests` | Unit tests for `PredicateBuilder` (Swift Testing) |

## Requirements

- macOS 27 or later
- Xcode with the macOS 27 SDK, Swift 6
- A Mac that supports Apple Intelligence, with Apple Intelligence turned on, for natural-language search,
  summaries, and questions. All other features work without it.

## Building

Open `NaturalSearch.xcodeproj` in Xcode, select the **NaturalSearch** scheme, and run it. On first launch,
add at least one folder under **Orte** so the app has something to search.
